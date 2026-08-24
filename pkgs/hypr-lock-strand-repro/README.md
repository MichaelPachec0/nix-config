# hypr-lock-strand-repro

Detects a Wayland compositor that returns from
`ext_session_lock_v1.get_lock_surface` without creating an object for the
client-allocated `new_id`.

```
nix run .
```

Exit codes: `0` survived (not affected), `1` killed (affected), `2` skipped
(preconditions unmet, nothing proven), `3` error.

## What it is checking

A Wayland `new_id` is allocated by the **client** and never acknowledged. The
client picks the number, sends the request, and from that moment treats the
object as existing. A compositor that declines to construct it leaves the
client holding a proxy for an id the compositor has never heard of, and does
not say so.

Nothing breaks at that point. It breaks on the next request to that proxy,
normally `destroy`, when `libwayland-server` cannot resolve the id and posts
`wl_display.error(0, "invalid object N")`. Protocol errors are fatal.

This tool drives that path on purpose:

1. take a session lock; the compositor grants it
2. ask for a second lock; a conforming compositor denies it and sends
   `finished`
3. call `get_lock_surface` on the **denied** lock, spending an id
4. unlock and restore the screen
5. destroy the denied lock (legal: `destroy` is only an error if `locked` was
   sent, and it was not)
6. destroy the id from step 3, and report which way it went

Step 4 happens before step 6 on purpose: if the compositor kills us at step 6,
the session is already unlocked.

## Safety

The session is locked for a fraction of a second and unlocked again before the
request under test is sent. The tool never reads input and never
authenticates. During the locked window the compositor shows its own fallback
surface, because this client deliberately draws nothing.

The residual risk is the ordinary one for any session-lock client: if the
process is killed between steps 1 and 4, the compositor keeps the session
locked with no client to unlock it. That is what `ext-session-lock-v1` is
designed to do. Recovery is a VT switch, or a second client permitted to
assume the orphaned lock.

## Preconditions

The compositor must **deny** a second concurrent session lock, which is the
default. On Hyprland that means:

```
misc:allow_session_lock_restore = false
```

With it enabled, Hyprland neither grants nor denies the second lock, the code
path under test is never entered, and the tool reports `SKIPPED` rather than
guessing. Check the live value with:

```
hyprctl getoption misc:allow_session_lock_restore
```

## Expected results

| Compositor | Expected |
| --- | --- |
| Hyprland through v0.56.2, unpatched | `KILLED` |
| Hyprland with the session-lock patch applied | `SURVIVED` |
| sway, or anything else on wlroots | `SURVIVED` |
| A compositor with no ext-session-lock-v1 | `SKIPPED` |

wlroots is unaffected because it creates the object before validating
anything and leaves it inert. Its own comment says so:

```c
	// We always need to create a lock surface resource to stay in sync
	// with the client, even if the lock resource or output resource is
	// inert. For example, if the compositor denies the lock and immediately
	// calls wlr_session_lock_v1_destroy() the client may have already sent
	// get_lock_surface requests.
```

That example is precisely the case this tool exercises.

## Verification status

Be precise about this when quoting results anywhere.

- **Builds clean.** `-Wall -Wextra -Werror`, and the derivation's
  `installCheckPhase` runs `--help`.
- **Runtime behaviour is unverified.** As of writing, the program has not been
  executed against any compositor. Nobody has yet seen it print `KILLED` or
  `SURVIVED`.

Do not describe it as a confirmed reproducer until someone has run it. If you
run it, record the compositor, its version, the value of
`misc:allow_session_lock_restore`, and the full stdout and stderr. The
compositor's own message, naming the stranded id, arrives on **stderr** via
libwayland's logging, not on stdout.

## Testing without risking a real session

Run it against a nested compositor instead of your desktop:

```
# terminal 1: a throwaway Hyprland in a window, with the precondition set
Hyprland -c /path/to/minimal.conf     # containing misc:allow_session_lock_restore = false

# terminal 2: point the tool at the nested instance
WAYLAND_DISPLAY=wayland-2 nix run .
```

The nested instance uses aquamarine's Wayland backend and is just a window, so
a stranded lock there costs nothing. Confirm the display name from the nested
compositor's startup output rather than assuming `wayland-2`.

## Consuming this from another flake

`default.nix` takes plain `callPackage` arguments and has no dependency on the
wrapper flake, so a host repo can do:

```nix
hypr-lock-strand-repro = pkgs.callPackage ./pkgs/hypr-lock-strand-repro {};
```

Dependencies are `wayland`, `wayland-scanner`, `wayland-protocols` and
`pkg-config`. The protocol bindings are generated at build time from the
`wayland-protocols` in scope rather than vendored, so the tool follows whatever
version the host repo pins.

`flake.nix` exists only so the directory can be copied somewhere and run
directly. Delete it if you are vendoring the package.

## Background

The defect this detects was found on Hyprland v0.56.2 in August 2026, from a
`WAYLAND_DEBUG` capture of a lock screen dying on resume:

```
[08:48:13.650896]  -> ext_session_lock_v1#520.get_lock_surface(
                        new id ext_session_lock_surface_v1#550,
                        wl_surface#540, wl_output#544)
[08:48:13.650961]     wl_registry#2.global_remove(75)
[08:48:14.095661]  -> ext_session_lock_surface_v1#550.destroy()
[08:48:14.104302]     wl_display#1.error(wl_display#1, 0, "invalid object 550")
```

The client sent the request 65 microseconds before being told the output was
gone, so it could not have avoided it. Three code paths in
`src/protocols/SessionLock.cpp` strand an id this way. This tool exercises the
one that needs no hardware and no race.
