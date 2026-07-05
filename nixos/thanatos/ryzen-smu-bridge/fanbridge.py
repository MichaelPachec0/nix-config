"""Pure, fully-typed fan-control decision core (no I/O)."""
from __future__ import annotations

from dataclasses import dataclass

# --- tunable constants (see spec) ------------------------------------------
ALPHA: float = 0.4          # EMA weight on newest sample
QUIET_OFFSET_C: float = 9.0  # C subtracted from control temp in quiet mode
FRESH_S: float = 6.0        # max SMU frame age before "stale"
SUSTAIN_S: float = 3.0      # hot condition hold time to force max fan
TCTL_HOT_C: float = 97.0    # raw Tctl safety threshold
PEAK_HOT_C: float = 100.0   # raw package peak safety threshold
FORCE_MAX_C: float = 99.0   # published temp when override fires
FAIL_SAFE_MC: int = 95000   # published on total sensor loss / exception
CLAMP_MIN_C: float = 0.0
CLAMP_MAX_C: float = 150.0

VALID_MODES: tuple[str, ...] = ("perf", "quiet")


@dataclass(frozen=True)
class Inputs:
    cpu_thm: float | None   # SMU filtered CPU temp; None if absent
    peak: float | None      # package_peaktemperature; None if absent
    tctl: float | None      # raw zenpower Tctl; None if unreadable
    frame_age: float        # seconds since last complete SMU frame (inf if none)
    ac_online: bool
    override: str | None    # "perf" | "quiet" | None
    now: float              # monotonic seconds


@dataclass(frozen=True)
class State:
    ema: float | None       # None until first tick seeds it
    hot_since: float | None  # monotonic ts hot began, else None


@dataclass(frozen=True)
class Decision:
    published_mc: int
    state: State


def parse_frame(text: str) -> dict[str, float]:
    """Parse one InfluxDB line-protocol frame into {key: float}. Non-numeric
    fields are skipped. Mirrors lib/influx.js parseFrame."""
    result: dict[str, float] = {}
    if not text:
        return result
    for raw_line in text.split("\n"):
        line = raw_line.strip()
        if not line:
            continue
        sp = line.find(" ")
        if sp < 0:
            continue
        for pair in line[sp + 1:].split(","):
            eq = pair.find("=")
            if eq < 0:
                continue
            key = pair[:eq]
            val = pair[eq + 1:]
            if val.endswith("i"):
                val = val[:-1]
            try:
                result[key] = float(val)
            except ValueError:
                continue
    return result


def resolve_mode(override: str | None, ac_online: bool) -> str:
    """Override if it is a valid mode, else auto: AC -> perf, battery -> quiet."""
    if override in VALID_MODES:
        assert override is not None
        return override
    return "perf" if ac_online else "quiet"
