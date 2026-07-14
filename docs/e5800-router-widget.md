# GL-E5800 Router Status Widget

A Quickshell task-bar widget that shows live status for a GL.iNet GL-E5800
portable 5G travel router, backed by a hardened NixOS system service. Read-only
except for three explicit modem-recovery actions.

- Device: GL.iNet GL-E5800, firmware 4.8.5, modem Quectel RG650V-NA (Qualcomm
  MHI/SMD), dual-SIM (physical T-Mobile active; eSIM empty), LAN 192.168.8.1.
- Host: `thanatos` (NixOS + Home-Manager). Bar: `features/hm/wayland/quickshell/task-bar`.

---

## 1. What it shows

**Bar item** (always present; JetBrainsMono text, FontAwesome glyphs):
- Connected: colored signal bars + `4G`/`5G` + router battery `%`.
- Reachable but SSH key rejected: a red warning glyph (re-auth needed).
- Not on the router: a dimmed `off` chip.

**Hover popup** (dashboard):
- Header: model, online dot, battery.
- Cellular hero: bars + gen + carrier, and colored `RSRP / RSRQ / SINR` + network type.
- Throughput (down/up) + plan-cycle data used.
- System health: CPU temp, load, uptime.
- Wi-Fi bands up + VPN tunnel state.
- Connected-clients list (name, IP, live rx/tx).
- Recovery panel: `Redial` / `Airplane` / `Reboot` (arm -> confirm).

---

## 2. Architecture

Credentials and all router I/O live in a hardened system service; the UI only
reads a sanitized artifact and can trigger three fixed recovery units.

```
sops-nix secrets --owner=e5800poll,0400--> /run/secrets/e5800/{ssh_key,web_password}
                                   |     (readable ONLY by root + the e5800poll user)
                    +--------------v-----------------------------+
                    | systemd system service  e5800-poll         |  (NixOS)
                    |  User=e5800poll, hardened sandbox           |
                    |  web-RPC dashboard + SSH ubus cellular       |
                    +--------------+-----------------------------+
                                   v writes DATA only
                         /run/e5800/status.json  (0644)
                                   |
                    +--------------v----------------+
                    | Quickshell (as your user)     |  (Home-Manager)
                    |  RouterService: polls the file |
                    |  -> RouterWidget + RouterPopup  |
                    +--------------------------------+
```

The UI never holds a secret, never opens SSH, and never authenticates. The one
write path (recovery) is three polkit-gated `systemctl start` calls.

---

## 3. Data sources

Two transports; the split is forced by the firmware.

**Web JSON-RPC** `POST http://192.168.8.1/rpc` (auth: `challenge` -> crypt the
password with `openssl passwd -<alg> -salt <salt>` -> `hash = sha256(user:cipher:nonce)`
-> `login` -> `sid`; then `call [sid, service, method, {}]`):
- `system.get_status` -- battery (mcu), CPU temp, load, memory, flash, uptime,
  client counts, active uplink (`network[]`), Wi-Fi list.
- `clients.get_speed` (throughput), `clients.get_list` (per-device),
  `vpn-client.get_status`, `lpm.get_status` (plugged), `system.get_info` (static).

**SSH ubus** `ssh root@192.168.8.1` (cellular signal + data usage are NOT exposed
to the web API):
- `ubus call cellular.collect get_signals '{"bus":"x"}'` -> newest signal:
  `{strength 0-5, network_type "NR5G-NSA"/"LTE"/..., rsrp, rsrq, sinr}`. The bus
  value is ignored (returns the active modem).
- Data usage: modem-interface byte counters from `/proc/net/dev` (the daemon's
  `get_traffic` needs an internal bus we could not obtain).
- Modem identity once: `ubus call modem.CPU.AT get_result_AT '{"cmd":"AT+CGMM",...}'`.

The service SSHes with host-key verification (TOFU): the first connect pins the
router's key into `/var/lib/e5800/known_hosts`; a later mismatch (rejected key or
a factory-reset's new host key) makes ssh exit 255, surfaced as `auth_error`.

---

## 4. status.json (service <-> UI contract)

```
{ "schema":1, "ts":<unix>, "reachable":bool, "auth_error":bool,
  "device":{model,firmware,modem,carrier},
  "battery":{percent,charging,plugged,fastcharge,temp},
  "uplink":{interface,online,up},
  "recovery":{active,action,started,result},
  "cellular":{supported,gen,network_type,strength,rsrp,rsrq,sinr,slot},
  "throughput":{rx,tx,unit},
  "data":{cycle_rx,cycle_tx,cycle_start,reset_day,source},
  "system":{cpu_temp,load[],mem_total,mem_free,mem_buff,flash_total,flash_free,uptime},
  "clients":{wireless,cable,usbeth,list:[{name,ip,online,rx,tx}]},
  "wifi":[{band,ssid,up,guest}],
  "vpn":{active,name,type} }
```

When `reachable=false` only `{schema,ts,reachable}` is written; the widget shows
the `off` chip.

## 5. Signal coloring

One shared helper `quality(metric, value)` -> good/fair/poor -> green/amber/red:

| Metric | green (good) | amber (fair) | red (poor) |
|--------|--------------|--------------|------------|
| RSRP   | >= -90 dBm   | -90 .. -105  | < -105     |
| RSRQ   | >= -11 dB    | -11 .. -16   | < -16      |
| SINR   | >= 13 dB     | 0 .. 13      | < 0        |

The bar's signal-bar tint uses the RSRP band; `strength` sets bar fill count.

---

## 6. Security model

- **sops-nix secrets** (in `secrets/default.yaml`, nested keys
  `e5800/ssh_key` + `e5800/web_password`), `owner = e5800poll`, `mode = 0400`.
  Only root and the service user can read them.
- **Dedicated system user** `e5800poll` (isSystemUser). The router's dropbear
  `authorized_keys` holds the matching ed25519 public key (`e5800poll.pub`).
- **Hardened poll service**: `ProtectHome`, `ProtectSystem=strict`,
  `NoNewPrivileges`, `PrivateTmp`, restricted syscalls/address families, empty
  capability set, `MemoryDenyWriteExecute`, `RestrictNamespaces`. Writable paths:
  `/run/e5800` (RuntimeDirectory) + `/var/lib/e5800` (StateDirectory, holds the
  persistent usage counter + known_hosts).
- **Artifact** `/run/e5800/status.json` (0644, data only) is the trust boundary.
- **Recovery**: three oneshot units + a polkit rule allowing your user to start
  exactly those three.

---

## 7. Setup (one-time)

Do these while connected to the E5800's Wi-Fi (gateway 192.168.8.1).

1. Generate a dedicated keypair:
   ```
   ssh-keygen -t ed25519 -N "" -f /tmp/e5800_key -C e5800poll
   cp /tmp/e5800_key.pub nixos/thanatos/e5800/e5800poll.pub   # version-controlled
   ```
2. Install the public key on the router (enter the admin password):
   ```
   ssh root@192.168.8.1 'mkdir -p /etc/dropbear && cat >> /etc/dropbear/authorized_keys' < /tmp/e5800_key.pub
   ssh -i /tmp/e5800_key root@192.168.8.1 'echo KEY_OK'   # prints KEY_OK, no password
   ```
3. Put the private key + web password into sops (nested):
   ```
   sed 's/^/        /' /tmp/e5800_key    # gives the key body indented for pasting
   sops secrets/default.yaml
   ```
   ```yaml
   e5800:
       ssh_key: |
           -----BEGIN OPENSSH PRIVATE KEY-----
           ...indented 8 spaces...
           -----END OPENSSH PRIVATE KEY-----
       web_password: <router admin password>
   ```
   Then `shred -u /tmp/e5800_key /tmp/e5800_key.pub`.
4. Enable the module -- in `flake.nix` thanatos `modules`:
   ```nix
   ./nixos/thanatos/e5800.nix
   { services.e5800.enable = true; }   # cycleResetDay = <plan day>; if not the 1st
   ```
5. Build, switch, verify:
   ```
   nixos-rebuild build --flake .#thanatos
   sudo nixos-rebuild switch --flake .#thanatos
   systemctl status e5800-poll
   cat /run/e5800/status.json | python3 -m json.tool     # reachable:true
   sudo -u e5800poll test -r /run/secrets/e5800/ssh_key && echo "service reads key"
   sudo -u <you> cat /run/secrets/e5800/ssh_key 2>&1 | grep -q 'Permission denied' && echo "you cannot (correct)"
   systemctl start e5800-redial.service && echo "polkit trigger OK"
   ```

The bar chip flips from `off` to live signal + `5G` + battery.

---

## 8. Recovery (the only writes)

Three fixed oneshot units (run as e5800poll, use the key), each one action:

| Button   | Unit                       | Action |
|----------|----------------------------|--------|
| Redial   | `e5800-redial.service`     | `ubus call network.interface.modem_cpu down` then `up` |
| Airplane | `e5800-airplane.service`   | `cellular.modem set_airplane_mode` on then off |
| Reboot   | `e5800-reboot-modem.service` | AT `AT+CFUN=1,1` (radio reset) via `modem.CPU.AT` |

Lifecycle: firing one writes `/run/e5800/recovery.json`; the poll service enters
a ~2 s constant-check, sets `recovery.active` (all three buttons disable), and
clears it when the uplink returns (>=8 s + 2 consecutive online reads) or after a
120 s timeout. The UI also latches optimistically on click.

---

## 9. Re-authentication (after a factory reset)

A factory reset wipes the router's `authorized_keys` and regenerates its SSH host
key, so the key stops working -> the service sets `auth_error` -> the bar shows a
red warning glyph and the popup shows a "SSH key rejected" banner.

Fix it with the provided helper (installed by the module):
```
e5800-provision-key
```
It re-appends `e5800poll.pub` to the router (prompts for the router password) and
clears the service's pinned host key (`/var/lib/e5800/known_hosts`, via sudo).
The poll service reconnects on its next cycle.

Manual equivalent:
```
ssh root@192.168.8.1 'cat >> /etc/dropbear/authorized_keys' < nixos/thanatos/e5800/e5800poll.pub
sudo rm -f /var/lib/e5800/known_hosts
```

---

## 10. Data usage (plan-cycle)

The metric is a running total that survives reconnects (recovery actions bounce
the modem and reset the raw interface counters). The service keeps a persistent
counter in `/var/lib/e5800/usage.json`: each SSH poll reads the modem netdev
bytes, adds the delta (or the full value when the counter reset), and zeroes on
the monthly `cycleResetDay`. If the modem netdev is not auto-detected, set
`services.e5800.netdev` (find it with `ssh ... 'cat /proc/net/dev'`).

---

## 11. Module options (`services.e5800`)

| Option          | Default              | Meaning |
|-----------------|----------------------|---------|
| `enable`        | false                | turn the poller on |
| `host`          | `http://192.168.8.1` | router base URL |
| `user`          | `root`               | router login user |
| `cycleResetDay` | `1`                  | plan-cycle reset day (1-28) |
| `netdev`        | `""` (auto)          | modem uplink netdev for byte counters |
| `triggerUser`   | `michael`            | user allowed to start recovery units |

---

## 12. Troubleshooting

- **Build fails in the module** -- fix `nixos/thanatos/e5800.nix`; the provision
  helper needs `e5800poll.pub` git-tracked (flakes ignore untracked files).
- **Service won't start (sandbox denial)** -- relax the offending hardening
  directive (`MemoryDenyWriteExecute` / `SystemCallFilter` are the usual ones for
  Python + ssh).
- **`status.json` reachable but `auth_error:true`** -- key rejected; run
  `e5800-provision-key`.
- **Widget stays `off` while the service writes status.json** -- the UI polls the
  file every 2 s (a plain file-watch breaks on the service's atomic rename); if
  still stale, confirm the file is 0644 and your user can read it.
- **Data usage empty** -- set `services.e5800.netdev` to the modem interface.

---

## 13. Files

Backend (NixOS): `nixos/thanatos/e5800.nix` (module) + `nixos/thanatos/e5800/`
(`e5800lib.py`, `e5800_poll.py`, `e5800_recover.py`, `test_e5800lib.py`,
`e5800poll.pub`). Enabled via `flake.nix`; secrets in `secrets/default.yaml`.

UI (Home-Manager, under `features/hm/wayland/quickshell/task-bar/`):
`lib/routerfmt.js`, `lib/RouterService.qml`, `desktop/RouterWidget.qml`,
`desktop/RouterPopup.qml`, `desktop/RouterClients.qml`; wired in `shell.qml` +
`desktop/Taskbar.qml`.
