# Repo maintenance tracker

A living list of known issues in this flake, grouped by **severity** with an **effort**
estimate (S = minutes, M = ~an hour, L = multi-hour). Check items off as they're fixed; move
them to the **Fixed log** with a date. Re-run the tooling below periodically to surface new
findings.

This file is documentation only — it is not imported by the flake.

## Tooling (regenerate findings)

```bash
nix flake check --no-build            # must stay exit 0 (whole-flake eval gate)
nix run nixpkgs#deadnix -- .          # dead code / unused bindings
nix run nixpkgs#statix -- check .     # anti-patterns (with/rec/etc.)
# Behaviour-preserving refactors: snapshot toplevel drvPaths before/after and diff them:
nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath
```

---

## Open issues

### High
_(none currently open — see Fixed log / Reviewed below)_

### Medium
- [ ] **systemPackages bloat (desktop)** · `features/nixos/desktop/wayland/default.nix:307-461`
  (~90 single-user GUI apps in a feature module) · **M** · move to home-manager or gate.
  *(The ~70 neovim LSPs are already gated — see Fixed log.)*
- [ ] **Rebuild-forcing overlays** · `features/nixos/kernel/{ntfs,native}.nix` (overlay
  `linuxPackages` -> full kernel rebuild; ntfs redundant with `boot.supportedFilesystems`),
  `features/nixos/virtualization/default.nix:99` (pinned qemu), `nixos/nyx/configuration.nix:1237`
  (pulls the entire `nerd-fonts` set) · **M**.
- [ ] **nyx eval/closure outliers** · `nyx:189-195` copies every input into `nix.registry`+`nixPath`;
  `nyx:768-769` `enableAllFirmware` + `enableAllHardware` together · **S**.
- [ ] **6 unused flake inputs + missing `follows`** · `flake.nix`
  (`nixpkgs-treesitter`, `hyprwm-contrib`, `nixos-cli`, `nixos-conf-editor`, `none-ls`, `jerry`;
  ~10 inputs lack `inputs.nixpkgs.follows`) · **S-M**.

### Low
- [ ] **~72 unused `let` bindings** (deadnix) · heaviest in `features/hm/wayland/default.nix`
  (`vpnStatus`, `waylandChecker`, `weakTargets`, `shaderFolder`, `denoise`, `geisha`…),
  `features/nixos/kernel/native.nix`, `features/hm/wayland/swayidle.nix` · **S** (`deadnix --edit`).
- [ ] **~340-line dead block** + dead `overlayList`/`mkOverlay` · `helpers/overlays.nix:655-996` · **S**.
- [ ] **Dead files (imported nowhere)** · top-level `gpg/`, `features/nixos/desktop/wayland/hyprModule.nix`,
  `features/hm/wayland/hydots.nix` (foreign dotfile w/ `/home/snes/` paths), `hyprland.conf.nix`,
  `waybar/config.hyprland`, `shaders/{reading_mode*,main.glsl}`, `helpers/externalModules.nix` · **S**.
- [ ] **Broken-if-imported files** · `pkgs/default.nix` (`callPackage ./shikane` — dir missing),
  `helpers/nixpkgs.nix` (`fetchTarball` + `narHash`-as-`sha256`) · **S** (delete).
- [ ] **Dead neovim modules + backups** · `features/hm/neovim/{nvchad.nix,nvchad.nix.bak,nvchad.patch_bak,default.nix}` · **S**.
- [ ] **`nvchad_b.nix` plugin list discarded** · `features/hm/neovim/nixneovim.nix:439-441` builds
  ~120 plugins then returns `in [];`. Decide `in plug;` vs delete; resolves whether ~20 custom
  `pkgs/vimPlugins/*` are live (incl. `mini-move` `fakeHash`, `sourcegraph`, `kitty-scrollback`,
  `block-nvim`, `coc-*` dead derivations) · **M**.
- [ ] **3 phantom inputs in dead/test paths** · `nix-colors` (`hm/home.nix:10`, `hm/home-test.nix:10`),
  `sp-test` (`hm/home-test.nix:8`), `nixpkgs-unstable` (`overlays/default.nix:15`) — latent eval
  errors if those paths are ever forced · **S**.
- [ ] **`with`/`rec` idioms** · top-of-module `with lib;`/`with pkgs;` (server/default.nix,
  auth/pam-u2f, kernel/native), `rec` in overrideAttrs (figma-linux, ncspot, qemu, flutter) · **S**.
- [ ] **Inert/contradictory config** · `ccache.enable=false` + populated `packageNames` (kore);
  unused `ipAddress` (`selene:12`); `kanshi` **and** `shikane` both active (pick one);
  two parallel waybar config sources · **S** each.
- [ ] **deadnix can't parse 5 files** — investigate (likely large inline-config-string modules) · **S**.

### Duplication (deferred 2026-06-09)
- [ ] **No `mkHost` builder** — `flake.nix:253-391` repeats the
  `nixpkgs.lib.nixosSystem { … specialArgs … modules = overlays.<ch>.<role> ++ […] }` scaffold
  across 6 hosts · **M**.
- [ ] **4 near-identical `sysadmin-*` home configs** — `flake.nix:445-485` differ only by
  `system`; generate via `listToAttrs`/`mapAttrs` · **S**.
- [ ] **`buildVimPlugin` boilerplate** — 26 of 27 `pkgs/vimPlugins/*/default.nix` share the same
  shape; extract a `helpers/buildPlugin.nix` wrapper + `callPackage` · **M** (pair with the
  `nvchad_b.nix` `in [];` decision, since many of those plugins aren't loaded).
- [ ] **Sway session env duplicated across hosts** — `hm/home-nyx.nix:10` and
  `hm/home-thanatos.nix:10` share a ~50-line `extraSessionCommands` + `swayfx.override`; extract
  `hm/sway-common.nix`, hosts pass only their delta · **M**.
- [ ] **Wayland env defined twice in one file** — `features/hm/wayland/default.nix` sets the same
  vars in the Hyprland `env` list (`:274-291`) and the sway `extraSessionCommands` (`:399-417`),
  plus `home.sessionVariables` declared twice. Hoist one `waylandEnv` attrset · **M**.

---

## Home-manager as a NixOS module (rollout in progress, started 2026-06-14)

Goal: build each user's home-manager config as part of `nixos-rebuild` while keeping
standalone `home-manager switch` working from the same modules. Decision:
`home-manager.useGlobalPkgs = true` (HM reuses system `pkgs`). Full design, blockers,
and rationale in `docs/hm-nixos-integration.md`.

Key invariant: a `standalone` module arg (default true, supplied via `extraSpecialArgs`)
toggles whether HM applies its own `nixpkgs.*`; under integration the system owns pkgs and
the HM-only overlay delta (`overlays.unstable.hmIntegrationOverlays`) is hoisted onto it.

### Done (committed)
- [x] **Shared module builder + `standalone` guard** · `helpers/home.nix`, `flake.nix`,
  `hm/home.nix`, `features/hm/common/default.nix`, `features/hm/wayland/default.nix` ·
  commit `fd448e7`. Standalone `michael-thanatos` activationPackage still evaluates.
- [x] **Integrated module + thanatos pilot + docs** · `features/nixos/home/default.nix`
  (`local.hm.*`), `helpers/overlays.nix` (`hmIntegrationOverlays`), `nixos/thanatos/extras.nix`,
  `docs/hm-nixos-integration.md` · commit `6139426`.

### In flight (uncommitted — fold into the test commit once thanatos/nyx build green)
- [ ] **nyx wired active** · `nixos/nyx/extras.nix` (new) + `flake.nix` nyx module list · **S**.
- [ ] **thanatos activated** · uncommented `./nixos/thanatos/extras.nix` in `flake.nix` · **S**.
- [ ] **`lspServers` path bug** · `helpers/overlays.nix:23-25` `./pkgs/...` -> `../pkgs/...`
  (was resolving under `helpers/`; latent until hoisted to the system) · **S** · done, uncommitted.
- [ ] **Dropped broken `pkgs/emmet-ls` override** · `helpers/overlays.nix` — it is a WIP stub
  (`npmDepsHash = lib.fakeHash`); now falls back to nixpkgs `emmet-language-server` · **S** · done, uncommitted.
- [ ] **kore wired (stable server)** · `nixos/kore/extras.nix` (new); `features/nixos/home/` split into
  `common.nix` (channel-agnostic core) + `default.nix` (unstable) + `stable.nix` (new); `helpers/overlays.nix`
  `stable.hmIntegrationOverlays`; `helpers/home.nix` non-desktop integrated branch (`[]`); `flake.nix` kore
  list (replaced `# overlays.stable.homeManager`). `desktop = false` -> no overlay hoist / no nixneovim · **M**.

### Remaining
- [ ] **Verify + switch thanatos, then nyx** · `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`
  before any switch. Watch for further `fakeHash`/stub packages pulled into `system-path`
  (next candidate: local `autotools-language-server`) · **S-M**.
- [ ] **aphrodite** · set `local.hm.enable`; then remove the now-redundant
  `inputs.home-manager.nixosModules.home-manager` import (`nixos/aphrodite/apple.nix:24-26`) and the
  `home-manager.useGlobalPkgs`/`useUserPackages` lines (`nixos/aphrodite/extras.nix:73-74`) —
  `features/nixos/home` owns them · **M**.
- [ ] **Delete `pkgs/emmet-ls`** stub dir now that nothing references it · **S** (pairs with the
  `fakeHash` cleanup already tracked under Low / `nvchad_b.nix`).
- [x] **Servers (sysadmin, stable channel)** · shared preset `features/nixos/home/server.nix`
  wires kore + selene + atlas (stable, `desktop = false`; kore/selene `toplevel` eval green).
  No server hosts left (eos has no `nixosConfiguration`). Standalone `sysadmin-*` configs untouched.
- [ ] **Delete dead scaffolding** once the new path is proven · `helpers/externalModules.nix`,
  `overlays.{stable,unstable}.homeManager` (`helpers/overlays.nix`) · **S** (also in Low / dead files).
- [ ] **Gate `report-changes` HM activation on `standalone`** · `features/hm/common/services.nix:18-22`
  — redundant with the system-level `nvd diff` under integration · **S**.
- [ ] **Move cache substituters to system `nix.settings`** for integrated hosts ·
  `helpers/caches.nix` — per-user nix.conf substituters are ignored for non-trusted users · **S**.
- [ ] **CI** · add integrated `nixosConfigurations.<host>...toplevel` builds to
  `.github/workflows/pr.yaml`; `home-manager-check.sh` only checks `homeConfigurations` · **S**.

### Security / hygiene (surfaced during testing)
- [ ] **Rotate the GitHub token exposed via the `nrsf` output**, then stop passing it on the
  command line · `features/hm/zsh/default.nix:124-125` (`hmsf`/`nrsf` inject
  `--option access-tokens "github.com=$(gh auth token)"`, which lands in logs/transcripts).
  Switch to reading from `GH_TOKEN`/a file or `~/.config/nix/nix.conf` `access-tokens` · **S**.

---

## Fixed log

### 2026-06-08 / 2026-06-09
- **Aligned Hyprland keyboard repeat with sway** — Hyprland had no `input` block (so it used the
  slow defaults 25 Hz / 600 ms); added `input.repeat_rate = 100; repeat_delay = 100;` to
  `wayland.windowManager.hyprland.settings` to match sway's 100/100 (same units; ints for
  Hyprland vs strings for sway).
- **Fixed `michael-nyx`/`michael-thanatos` home build** — `wayland.windowManager.sway.config.input`
  had bare int `repeat_rate`/`repeat_delay`; moved them under a `"type:keyboard"` criteria with
  string values (`features/hm/wayland/default.nix`). Both activationPackages now evaluate.
- **Deduped SSH public keys** — every authorized key now lives once in `helpers/keys.nix` (9 named keys
  + `all`/`laptops`/`initrd` bundles), referenced from the 4 hosts + `deploy.nix` (was ~41
  copy-pasted lines across 6 files, including kore's internal duplicates and a trailing-space
  variant). Verified **access-preserving**: the resolved authorized-key set for every
  host/user/initrd is byte-identical before/after.
- **Deduped hm `nixpkgs.config`** — `allowUnfree`/`allowUnfreePredicate` moved into
  `features/hm/common/default.nix` (imported by all 3 hm entrypoints) and removed from
  `home.nix`/`home-test.nix`/`sysadmin.nix`. `sysadmin-kore` activationPackage drvPath unchanged.
- **Server-host dedup** — extracted the config shared by kore/atlas/selene into
  `features/nixos/server/base.nix` (nix settings, `80-iwd` link, zerotier, openssh, common
  `sysadmin` attrs, timezone, uptimed, nameservers, allowUnfree, zram enable, stateVersion).
  Each host keeps its own SSH keys/shell + host specifics. Verified **behaviour-preserving**:
  kore/atlas/selene `toplevel.drvPath` byte-identical before/after.
- **Gated neovim LSPs/formatters** behind `devMachine.enable`
  (`features/nixos/desktop/common/neovim.nix`, `lib.mkIf config.devMachine.enable`). No-op for the
  current fleet (nyx/thanatos/aphrodite all set `devMachine.enable=true`; verified all ~70 packages
  still present on nyx — the drvPath shifts only because `mkIf` re-orders the profile `buildEnv`).
- **Bugs fixed:** power-key typo `powerfoff`->`poweroff` (`nyx:1339`); wireplumber output config
  was clobbering input (both wrote `51-gbuds_input.conf` -> output now `51-gbuds_output.conf`);
  usbip stop script `$port` used before assignment (reordered, `usbip/services.nix`);
  removed `rust-rover` phantom-input landmine (`helpers/overlays.nix`).
- **Deprecations cleared** (`nix flake check` was warning, now clean): `hardware.opengl`->
  `hardware.graphics` (kore); `pkgs.system`/`prev.system`->`stdenv.hostPlatform.system` (overlays +
  several modules); `networking.wireless.userControlled.enable`->`userControlled` (nyx);
  `fonts.fonts`->`fonts.packages` (nyx); removed deprecated nixos-hardware `common-pc-hdd` (kore);
  `greetd.regreet`->`regreet` (login module).
- **`alex` made evaluable** — imports its `hardware-configuration.nix`, enables systemd-boot+EFI,
  disables grub, sets `system.stateVersion`. `nix flake check --no-build` now exits 0.

---

## Reviewed — non-issues (do not re-flag)

- **`gkey` geolocation key** (`nixos/nyx/configuration.nix:~1297`) — this is the **public**
  Google geolocation key Arch ships; not a secret, zero impact. Intentional, leave as-is.
- **Repo-root clutter** (~50 `flake.lock_*` backups, large `failure*.txt`, `kore`/`test.txt`
  blobs) — out of scope by request (Nix-code focus only). Noted for awareness; not tracked here.
