#!/usr/bin/env python3
"""Perform ONE fixed E5800 modem-recovery action over SSH, and mark it active
so the poll service enters constant-check mode. Read-limited: only the three
predefined actions; no arbitrary commands."""
import json
import os
import subprocess
import sys
import time

USER = os.environ.get("E5800_USER", "root")
HOST = os.environ.get("E5800_HOST", "http://192.168.8.1").split("//")[-1].split("/")[0]
SSH_KEY = os.environ.get("E5800_SSH_KEY", "")
RUNTIME = os.environ.get("E5800_RUNTIME", "/run/e5800")
STATE = os.environ.get("E5800_STATE", "/var/lib/e5800")

RECOVER_CMDS = {
    "redial": [
        "ubus call network.interface.modem_cpu down",
        "sleep 3",
        "ubus call network.interface.modem_cpu up",
    ],
    "airplane": [
        "ubus call cellular.modem set_airplane_mode '{\"enable\":true}'",
        "sleep 3",
        "ubus call cellular.modem set_airplane_mode '{\"enable\":false}'",
    ],
    "reboot": [
        "ubus call modem.CPU.AT get_result_AT "
        "'{\"cmd\":\"AT+CFUN=1,1\",\"timeout\":10,\"source_flag\":0,\"sub_id\":0}'",
    ],
}


def _ssh(cmd):
    # -F /dev/null: ignore the system ssh_config (see e5800_poll._ssh) so the
    # gpg-agent `Match host * exec` hook is not run via e5800poll's nologin shell.
    args = ["ssh", "-F", "/dev/null", "-i", SSH_KEY, "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile={}/known_hosts".format(STATE),
            "-o", "ConnectTimeout=5",
            "{}@{}".format(USER, HOST), cmd]
    subprocess.run(args, timeout=30)


def _mark(action):
    os.makedirs(RUNTIME, exist_ok=True)
    tmp = os.path.join(RUNTIME, "recovery.json.tmp")
    with open(tmp, "w") as f:
        json.dump({"action": action, "started": int(time.time())}, f)
    os.replace(tmp, os.path.join(RUNTIME, "recovery.json"))


def main():
    args = sys.argv[1:]
    printonly = "--print" in args
    args = [a for a in args if a != "--print"]
    if not args or args[0] not in RECOVER_CMDS:
        sys.stderr.write("usage: e5800_recover.py [--print] <redial|airplane|reboot>\n")
        sys.exit(2)
    action = args[0]
    cmds = RECOVER_CMDS[action]
    if printonly:
        print("\n".join(cmds))
        return
    _mark(action)
    for c in cmds:
        _ssh(c)


if __name__ == "__main__":
    main()
