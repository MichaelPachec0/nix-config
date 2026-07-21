#!/usr/bin/env bash
# Current backlight brightness as a bare percentage (no % sign) for the hub
# ButtonsSlidersCard brightness slider. Prints nothing on failure (parser
# defaults to 50).
set -u

brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '% ' || true
