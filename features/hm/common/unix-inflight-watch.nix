# Forensics for the AF_UNIX in-flight fd cliff, which ./dbus-fd-watch.nix
# cannot see: that samples how many fds dbus-broker HOLDS, and in this failure
# nothing's fd count is high because the fds are in flight.
#
# The kernel keeps a per-UID count of fds sent via SCM_RIGHTS but not yet
# received, and net/unix/scm.c fails any further SCM_RIGHTS sendmsg() with
# ETOOMANYREFS once it exceeds the SENDING task's soft RLIMIT_NOFILE. Nothing
# exports that counter, so the only way to read it is to attempt a send under a
# chosen soft limit and see whether it fails -- /proc/<pid>/fd, lsof, ss and
# file-nr all look healthy while it is fatal, which is why it took hours to
# diagnose the first time.
#
# It gets stuck because queued messages carrying unix-socket fds form reference
# cycles that only unix_gc() can free, and the kernel runs that sweep only above
# UNIX_INFLIGHT_TRIGGER_GC (16000). A leak of a few thousand therefore sits
# below the collection threshold forever while already far above the default
# 1024 soft limit (observed: 89 orphaned sockets pinning ~2470 fds until
# reboot). Hyprland hands its children that 1024 default even though it runs at
# 524288 itself, so every keybind-launched GUI app dies at Wayland connect with
# "Too many references: cannot splice" -- which presents as "keybinds stopped
# working", not as an fd problem.
#
#   journalctl --user -u unix-inflight-watch -b
{pkgs, ...}: let
  # Probe: can a task with soft RLIMIT_NOFILE=N still pass an fd? Bisects for
  # the in-flight count when asked, otherwise a cheap yes/no at one threshold.
  # Plain text plus an explicit interpreter rather than writers.writePython3,
  # which gates the build on flake8 and would turn a lint nit in a diagnostic
  # script into a failed nixos-rebuild.
  probeSrc = pkgs.writeText "unix-inflight-probe.py" ''
    import array
    import os
    import resource
    import socket
    import sys


    def can_pass(limit):
        """True if a task with soft RLIMIT_NOFILE=limit can still send an fd."""
        hard = resource.getrlimit(resource.RLIMIT_NOFILE)[1]
        if limit > hard:
            return True
        try:
            resource.setrlimit(resource.RLIMIT_NOFILE, (limit, hard))
        except (ValueError, OSError):
            return True
        a, b = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
        fd = os.open(os.devnull, os.O_RDONLY)
        try:
            a.sendmsg([b"x"], [(socket.SOL_SOCKET, socket.SCM_RIGHTS,
                                array.array("i", [fd]))])
            return True
        except OSError:
            return False
        finally:
            os.close(fd)
            a.close()
            b.close()


    def bisect():
        lo, hi = 64, 524288
        while hi - lo > 64:
            mid = (lo + hi) // 2
            if can_pass(mid):
                hi = mid
            else:
                lo = mid
        return lo


    if __name__ == "__main__":
        # `check <limit>` -> exit 0 if fd passing still works at that limit.
        # `count`         -> print the bisected in-flight estimate.
        if sys.argv[1] == "check":
            sys.exit(0 if can_pass(int(sys.argv[2])) else 1)
        print(bisect())
  '';
  probe = "${pkgs.python3}/bin/python3 ${probeSrc}";

  watcher = pkgs.writeShellApplication {
    name = "unix-inflight-watch";
    runtimeInputs = with pkgs; [coreutils gawk iproute2 systemd procps];
    text = ''
      # Without this an unmatched glob expands to the literal pattern and the
      # socket counts below would read 1 instead of 0.
      shopt -s nullglob

      interval=''${UNIX_INFLIGHT_INTERVAL:-10}     # cheap probe, seconds
      heartbeat=''${UNIX_INFLIGHT_HEARTBEAT:-900}  # trend line, seconds
      # The threshold that actually matters: systemd's default soft limit. Once
      # in-flight passes this, every process still on that default is broken.
      floor=''${UNIX_INFLIGHT_FLOOR:-1024}

      # Queued bytes with no owning process: the stranded cycles. Healthy is 0.
      orphans() {
        ss -x -a -p 2>/dev/null \
          | awk '($3+0)>0 && $0 !~ /users:/ {n++} END{print n+0}'
      }

      # Everything worth knowing at the moment it breaks, so the next occurrence
      # does not have to be reproduced.
      forensics() {
        local inflight=$1 orph=$2
        echo "DEGRADED inflight~=$inflight orphan_sockets=$orph"
        echo "  -- queued sockets by owner --"
        ss -x -a -p 2>/dev/null | awk '($3+0)>0' \
          | grep -oE 'users:\(\("[^"]+",pid=[0-9]+' | sort | uniq -c | sort -rn \
          | head -n 10 | while read -r line; do echo "    $line"; done || true
        echo "  -- unowned (stranded) queued sockets: $(ss -x -a -p 2>/dev/null | awk '($3+0)>0 && $0 !~ /users:/' | wc -l) --"
        echo "  -- recent core dumps --"
        # Layout is: <4 time fields> PID UID GID SIG COREFILE EXE SIZE, so the
        # executable is $(NF-1). $NF is the core size, which is not what we want.
        coredumpctl list --since -10min --no-pager --no-legend 2>/dev/null \
          | awk '{n=split($(NF-1),p,"/"); print p[n]}' \
          | sort | uniq -c | sort -rn | head -n 5 \
          | while read -r line; do echo "    $line"; done || true
        echo "  -- dbus activations in the last 10min (storm detector) --"
        journalctl --user --since -10min --no-pager 2>/dev/null \
          | grep -oE 'Started dbus-[^ ]+\.service' | sort | uniq -c | sort -rn \
          | head -n 5 | while read -r line; do echo "    $line"; done || true
        # A climbing eis-* count alongside a climbing orphan count is the xdph
        # EIS leak specifically. Counts FILES, and each session leaves a socket
        # plus its .lock, so this reads ~2x the session count; the trend is the
        # signal, not the absolute number.
        local rt eis way
        rt="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        eis=("$rt"/eis-*)
        way=("$rt"/wayland-*)
        echo "  -- runtime files: eis=''${#eis[@]} wayland=''${#way[@]} (eis ~2 per session) --"
      }

      echo "watching AF_UNIX in-flight fds (floor=$floor, interval=''${interval}s)"
      degraded=0
      last_beat=0
      while :; do
        now=$SECONDS
        if ${probe} check "$floor"; then
          if [ "$degraded" = 1 ]; then
            echo "RECOVERED fd passing works again at soft=$floor (in-flight fell below it, or a reboot cleared it)"
            degraded=0
          fi
          if [ $((now - last_beat)) -ge "$heartbeat" ]; then
            echo "sample ok floor=$floor orphan_sockets=$(orphans)"
            last_beat=$now
          fi
        else
          # Only pay for the bisect + dump on the transition, not every tick.
          if [ "$degraded" = 0 ]; then
            forensics "$(${probe} count)" "$(orphans)"
            degraded=1
            last_beat=$now
          elif [ $((now - last_beat)) -ge "$heartbeat" ]; then
            echo "still degraded inflight~=$(${probe} count) orphan_sockets=$(orphans)"
            last_beat=$now
          fi
        fi
        sleep "$interval"
      done
    '';
  };
in {
  systemd.user.services.unix-inflight-watch = {
    Unit.Description =
      "Sample AF_UNIX in-flight fd pressure (ETOOMANYREFS / stranded-socket forensics).";
    Service = {
      ExecStart = "${watcher}/bin/unix-inflight-watch";
      Restart = "always";
      RestartSec = 5;
      Nice = 10;
      SyslogIdentifier = "unix-inflight-watch";
    };
    Install.WantedBy = ["default.target"];
  };
}
