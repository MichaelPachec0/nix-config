#!/usr/bin/env bash
# Human-readable uptime with the leading "up " stripped, for PowerMenuGrid.qml.
set -u

uptime -p | sed -e 's/^up //'
