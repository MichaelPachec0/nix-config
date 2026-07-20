#!/usr/bin/env bash
# Region screenshot (grim + slurp), matching common.nix's helper. Saved to
# ~/Pictures/scrn-<iso-timestamp>.png. Fired by the hub after the overlay closes.
set -u

grim -t png -g "$(slurp)" "$HOME/Pictures/scrn-$(date +%Y-%m-%dT%H:%M:%S%:z).png"
