#!/usr/bin/env bash
# Copy the first argument to the Wayland clipboard verbatim, with no trailing
# newline (printf '%s'). Shared by the network detail rows and the process list.
set -u

printf '%s' "${1:-}" | wl-copy
