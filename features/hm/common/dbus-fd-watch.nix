{pkgs, ...}: let
  # Forensics for the user session bus dying on EMFILE (see the LimitNOFILE
  # comment in nixos/nyx/configuration.nix). The limit fix stops the session from
  # being torn down, but it does not answer *who* held ~460 concurrent
  # connections. This samples the pressure continuously so the answer is already
  # in the journal the next time it climbs, instead of needing a live repro.
  #
  # Read it back with:
  #   journalctl --user -u dbus-fd-watch -b            # this boot
  #   journalctl --user -u dbus-fd-watch -b -1 | tail  # the boot that died
  watcher = pkgs.writeShellApplication {
    name = "dbus-fd-watch";
    runtimeInputs = with pkgs; [systemd procps coreutils findutils gawk gnused];
    text = ''
      shopt -s nullglob

      interval=''${DBUS_FD_WATCH_INTERVAL:-1}       # fd poll, seconds
      heartbeat=''${DBUS_FD_WATCH_HEARTBEAT:-300}   # trend line, seconds
      warn_pct=''${DBUS_FD_WATCH_WARN_PCT:-50}      # start dumping peers
      crit_pct=''${DBUS_FD_WATCH_CRIT_PCT:-75}      # dump per-pid too
      detail_gap=''${DBUS_FD_WATCH_DETAIL_GAP:-30}  # min seconds between dumps

      # Peer counts and the fd-type split. The split is the discriminator:
      # dbus-broker spends ~2 fds per connected peer (one socket + one
      # anon_inode), so if fds climb while the socket count does not, the fds are
      # queued in undelivered messages (fd passing) rather than held by peers.
      detail() {
        local pid=$1 fds=$2 soft=$3 level=$4 conns
        conns=$(busctl --user list --unique --no-legend 2>/dev/null | wc -l || true)
        echo "$level detail fds=$fds/$soft conns=$conns"
        find "/proc/$pid/fd" -maxdepth 1 -type l -printf '%l\n' 2>/dev/null \
          | sed 's/\[.*/[anon]/' | sort | uniq -c | sort -rn \
          | while read -r count kind; do echo "  fdtype $kind count=$count"; done || true
        busctl --user list --unique --no-legend 2>/dev/null \
          | awk '$3 != "-" {print $3}' | sort | uniq -c | sort -rn | head -n 15 \
          | while read -r count comm; do echo "  peers comm=$comm count=$count"; done || true
        if [ "$level" = "CRIT" ]; then
          busctl --user list --unique --no-legend 2>/dev/null \
            | awk '$2 != "-" {print $2}' | sort | uniq -c | sort -rn | head -n 20 \
            | while read -r count peerpid; do
              echo "  peers pid=$peerpid count=$count cmd=$(tr '\0' ' ' 2>/dev/null < "/proc/$peerpid/cmdline" | cut -c1-120 || true)"
            done || true
        fi
      }

      while :; do
        pid=$(pgrep -u "$(id -u)" -x dbus-broker | head -n1 || true)
        if [ -z "$pid" ]; then
          sleep 5
          continue
        fi
        soft=$(awk '/Max open files/ {print $4}' "/proc/$pid/limits")
        echo "watching dbus-broker pid=$pid soft_nofile=$soft"

        peak=0
        last_detail=0
        last_beat=0
        while [ -d "/proc/$pid" ]; do
          # Glob instead of `ls | wc -l`: no fork on the hot path.
          fda=("/proc/$pid/fd"/*)
          fds=''${#fda[@]}
          pct=$((fds * 100 / soft))
          now=$SECONDS

          if [ "$fds" -gt "$peak" ]; then
            peak=$fds
            echo "peak fds=$fds/$soft pct=$pct"
          fi

          level=""
          if [ "$pct" -ge "$crit_pct" ]; then
            level=CRIT
          elif [ "$pct" -ge "$warn_pct" ]; then
            level=WARN
          fi
          if [ -n "$level" ] && [ $((now - last_detail)) -ge "$detail_gap" ]; then
            detail "$pid" "$fds" "$soft" "$level"
            last_detail=$now
          fi

          if [ $((now - last_beat)) -ge "$heartbeat" ]; then
            echo "sample fds=$fds/$soft pct=$pct peak=$peak"
            last_beat=$now
          fi

          sleep "$interval"
        done
        echo "dbus-broker pid=$pid gone (peak fds=$peak/$soft); re-resolving"
      done
    '';
  };
in {
  systemd.user.services.dbus-fd-watch = {
    Unit = {
      Description = "Sample user dbus-broker fd pressure (session-bus EMFILE forensics).";
      # Deliberately not bound to the bus: it must outlive a broker restart and
      # keep sampling across it.
    };
    Service = {
      ExecStart = "${watcher}/bin/dbus-fd-watch";
      Restart = "always";
      RestartSec = 5;
      Nice = 10;
      SyslogIdentifier = "dbus-fd-watch";
    };
    Install.WantedBy = ["default.target"];
  };
}
