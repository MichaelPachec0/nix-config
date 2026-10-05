#⋅kitty-scrollback.nvim⋅Kitten⋅alias↴
# action_alias⋅kitty_scrollback_nvim⋅kitten⋅/home/michael/.config/nvim/lazyPlugins/pack/lazyPlugins/start/kitty-scrollback.nvim/python/kitty_scrollback_nvim.py↴
# ↴
#⋅Browse⋅scrollback⋅buffer⋅in⋅nvim↴
# map⋅kitty_mod+h⋅kitty_scrollback_nvim↴
#⋅Browse⋅output⋅of⋅the⋅last⋅shell⋅command⋅in⋅nvim↴
# map⋅kitty_mod+g⋅kitty_scrollback_nvim⋅--config⋅ksb_builtin_last_cmd_output↴
#⋅Show⋅clicked⋅command⋅output⋅in⋅nvim↴
# mouse_map⋅ctrl+shift+right⋅press⋅ungrabbed⋅combine⋅:⋅mouse_select_command_output⋅:⋅kitty_scrollback_nvim⋅--config⋅ksb_builtin_last_visited_cmd_output↴
{
  pkgs,
  lib,
  ...
}: let
  # Proactive reclaim for kitty. kitty keeps its pager history
  # (scrollback_pager_history_size) as a plain heap ring buffer: there is no
  # disk backing. kitty only writes at the ring head, so the older pages go
  # cold, but the kernel only reclaims under memory pressure, and with free RAM
  # they stay resident. This pushes the cold anon pages of each kitty scope into
  # zswap (zstd, still RAM, ~3-5x smaller for text); kitty_mod+h faults them
  # back in.
  #
  # One scope per kitty instance (app-run gives each launch its own
  # app-*-kitty-*.scope). A scope also holds the shells and programs run in
  # it, so the floor keeps a hot working set resident for the whole tree.
  #
  # Measure against `anon` from memory.stat, not memory.current:
  # memory.current also counts the compressed zswap pool charged to the
  # cgroup, and that pool cannot shrink further (zswap shrinker is off), so a
  # current-based target would evict hot pages on every run.
  kittyReclaim = pkgs.writeShellApplication {
    name = "kitty-reclaim";
    runtimeInputs = [pkgs.coreutils pkgs.findutils pkgs.gawk];
    text = ''
      floor=$((256 * 1024 * 1024))
      base="/sys/fs/cgroup/user.slice/user-$UID.slice/user@$UID.service/app.slice"
      [[ -d $base ]] || exit 0

      while IFS= read -r -d "" scope; do
        # The scope can exit between find and here; skip it if so.
        anon=$(awk '$1 == "anon" { print $2 }' "$scope/memory.stat" 2>/dev/null) || continue
        [[ -n $anon ]] || continue
        excess=$((anon - floor))
        ((excess > 0)) || continue
        # swappiness=max: reclaim anon only. The kernel returns EAGAIN when
        # it frees less than asked; that is not a failure here.
        echo "$excess swappiness=max" >"$scope/memory.reclaim" 2>/dev/null || true
      done < <(find "$base" -maxdepth 3 -type d -name 'app-*kitty*.scope' -print0)
    '';
  };

  # Shared with settings below: the soft reset flushes exactly this many lines
  # to push the live buffer into the pager history, and it finds kitty's
  # remote-control socket from this path.
  scrollbackLines = 10000;
  listenOn = "unix:/tmp/kitty";

  # kitty_mod+delete: get back to a sane shell prompt WITHOUT losing history.
  #
  # kitty's own reset (clear_terminal reset / RIS / `reset`) calls
  # historybuf_clear(), which also frees the pager history. This does not.
  # It runs as a kitty background launch, so it works even when the window
  # itself cannot take input: kitty reads its shortcuts before it encodes keys
  # for the program.
  #
  # 1. Find what owns the terminal: the tty's foreground process group
  #    (tpgid), the same group ctrl+C and kitty's signal_child target.
  # 2. If that is a shell (the window's own, or a nested one from nix develop
  #    / sudo -s), send no signal. If it is a pass-through client (ssh, mosh,
  #    tmux, zellij), send no signal and do nothing else: the garbage comes
  #    from the far side, and writing to the tty under it breaks the session.
  # 3. Otherwise escalate one step per press: SIGINT, then SIGTERM, then
  #    SIGKILL, with presses at most 5 s apart. One stray press can at most
  #    SIGINT something; SIGKILL needs three deliberate presses.
  # 4. Only when a shell owns the terminal again: write mode resets into the
  #    pty SLAVE (kitty parses that as program output), flush the live buffer
  #    into the pager history with newlines, and send ctrl+L so zsh redraws
  #    its prompt. A program that survived the signal keeps its terminal state
  #    untouched.
  #
  # No `stty sane`: zsh restores its own termios every time it regains the
  # foreground, and changing termios under an active zle would break it.
  kittySoftReset = pkgs.writeShellApplication {
    name = "kitty-soft-reset";
    # kitten comes from the system kitty on PATH (programs.kitty.package is
    # emptyDirectory), so it always matches the running kitty.
    runtimeInputs = [pkgs.coreutils pkgs.procps pkgs.jq pkgs.libnotify];
    text = ''
      wid=$1
      # A background launch gets no KITTY_LISTEN_ON; kitty is our parent and
      # listen_on appends its pid to the socket path.
      to=''${KITTY_LISTEN_ON:-${listenOn}-$PPID}
      state_dir=''${XDG_RUNTIME_DIR:-/run/user/$UID}/kitty-soft-reset
      state=$state_dir/$wid
      mkdir -p "$state_dir"

      shell_pid=$(kitten @ --to "$to" ls --match "id:$wid" |
        jq -r --argjson w "$wid" '[.[].tabs[].windows[] | select(.id == $w)][0].pid')
      [[ $shell_pid =~ ^[0-9]+$ ]] || exit 0
      tty=/dev/$(ps -o tty= -p "$shell_pid" | tr -d ' ')

      fg_pgid() { ps -o tpgid= -p "$shell_pid" | tr -d ' '; }
      fg_comm() {
        local c member
        c=$(ps -o comm= -p "$1" 2>/dev/null) || c=""
        # The group leader may have exited; fall back to any member.
        if [[ -z $c ]]; then
          member=$(pgrep -g "$1" | head -n1) || member=""
          [[ -z $member ]] || c=$(ps -o comm= -p "$member" 2>/dev/null) || c=""
        fi
        echo "$c"
      }
      is_shell() { [[ $1 == "$shell_pid" ]] || [[ $2 =~ ^-?(zsh|bash|fish|sh|dash|nu)$ ]]; }
      is_passthrough() { [[ $1 =~ ^(ssh|mosh-client|tmux|tmux:.*|zellij)$ ]]; }

      soft_reset() {
        local rows
        rows=$(stty -F "$tty" size 2>/dev/null | cut -d' ' -f1) || rows=""
        [[ $rows =~ ^[0-9]+$ ]] || rows=100
        {
          # G0 charset + shift-in, attributes, scroll region, origin mode off,
          # autowrap on, cursor visible, cursor keys + keypad normal.
          printf '\e(B\x0f\e[0m\e[r\e[?6l\e[?7h\e[?25h\e[?1l\e>'
          # Leave the alternate screen, all mouse modes + focus reporting off,
          # end any synchronized update, pop the kitty keyboard protocol stack.
          printf '\e[?1049l\e[?1000;1002;1003;1004;1005;1006;1015;1016l\e[?2026l\e[<99u'
          # Cursor shape default; palette, fg, bg and cursor colors default.
          # OSCs end in BEL, not ESC-backslash, which trips shellcheck SC1003.
          printf '\e[ q\e]104\a\e]110\a\e]111\a\e]112\a'
          # Flush: from the bottom row, push the whole live buffer (screen +
          # scrollback_lines) off into the pager history.
          printf '\e[999;1H'
          head -c "$((${toString scrollbackLines} + rows))" /dev/zero | tr '\0' '\n'
        } >"$tty"
        printf '\f' | kitten @ --to "$to" send-text --match "id:$wid" --stdin
        rm -f "$state"
      }

      pgid=$(fg_pgid)
      comm=$(fg_comm "$pgid")
      if is_shell "$pgid" "$comm"; then
        soft_reset
        exit 0
      fi
      if is_passthrough "$comm"; then
        notify-send -a kitty "kitty soft reset" "Skipped: $comm owns the terminal. Reset the remote side, or use ctrl+shift+alt+delete."
        exit 0
      fi

      # Presses more than 5 s apart start over at SIGINT.
      now=$(date +%s)
      count=0
      if [[ -f $state ]]; then
        read -r last_count last_time <"$state" || true
        if ((now - ''${last_time:-0} <= 5)); then count=''${last_count:-0}; fi
      fi
      count=$((count + 1))
      case $count in
        1) sig=INT next=SIGTERM ;;
        2) sig=TERM next=SIGKILL ;;
        *) sig=KILL next=SIGKILL ;;
      esac
      kill -s "$sig" -- "-$pgid" 2>/dev/null || true

      # Give the group up to ~500 ms to die and the shell to take the tty back.
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        sleep 0.05
        pgid=$(fg_pgid)
        comm=$(fg_comm "$pgid")
        if is_shell "$pgid" "$comm"; then
          soft_reset
          exit 0
        fi
      done

      echo "$count $now" >"$state"
      notify-send -a kitty "kitty soft reset" "Sent SIG$sig; $comm still running. Press again within 5 s for $next."
    '';
  };

  # kitty_mod+alt+delete: kitty's real hard reset (its default kitty_mod+delete
  # binding, moved here), snapshot first. The full history, pager history
  # included (@ansi_screen_scrollback goes through as_text(add_history=True)),
  # is captured in kitty's main process before clear_terminal runs, then
  # written here. Read one back with `zstdcat <file> | less -R`. Terminal
  # output can hold secrets, so the files are 0600 and pruned after 30 days.
  kittySnapshot = pkgs.writeShellApplication {
    name = "kitty-snapshot";
    runtimeInputs = [pkgs.coreutils pkgs.findutils pkgs.zstd];
    text = ''
      dir=''${XDG_STATE_HOME:-$HOME/.local/state}/kitty-snapshots
      umask 077
      mkdir -p "$dir"
      zstd -q -o "$dir/$(date +%F_%H%M%S)-w''${1:-x}.ansi.zst"
      find "$dir" -name '*.ansi.zst' -mtime +30 -delete
    '';
  };
in {
  imports = [];
  options = {};
  config = {
    # nixpkgs = {
    #   overlays =
    #     [ (final: prev: { inherit (pkgs.unstable) kitty-themes; }) ];
    # };
    programs = {
      kitty = let
        test_font = "FranSans-Tile";
        base_font = "JetBrainsMonoNFM";
        font = "${base_font}-Regular";
        bold_font = "${base_font}-Bold";
        italic_font = "${base_font}-Italic";
        BI_font = "${base_font}-BoldItalic";
      in {
        enable = true;
        package = pkgs.emptyDirectory;
        # NOTE: might contribute extra options to this, a module for theme that can specify the package as well
        theme = "Gruvbox Material Dark Hard";
        font = {
          # NOTE: This should be install globally as part of fontConfig
          # prefer this to FiraCode, the r's are more readable with the current size
          name = font;
          # name = test_font;
          size = 9;
        };
        shellIntegration.enableZshIntegration = true;
        settings = {
          # Disable kitty's built-in config hot-reload. Its watcher
          # (kitten __watch_conf__) follows the nix-store symlink of kitty.conf
          # and recursively watches /nix/store, accumulating ~64k inotify
          # watches and exhausting fs.inotify.max_user_watches for the user --
          # which starves every other inotify consumer (waybar battery,
          # dbus-broker cgroups, ...). Home Manager reloads kitty on switch
          # instead (see home.activation.reloadKitty below).
          auto_reload_config = -0.1;
          # remember_window_size also replays the last closed window's
          # maximized state (~/.cache/kitty/main.json "window-state"): every
          # new kitty sends xdg_toplevel.set_maximized after its first frame.
          # On Hyprland that puts the workspace in fullscreen mode, and hy3
          # refuses every focus/tab dispatcher while a workspace has a
          # fullscreen window, so tabs look stacked but stop cycling. The
          # tiler owns window size here, so remember nothing.
          remember_window_size = false;
          # Want a huge buffer. 100000 in-memory lines is the wrong way to get
          # it -- upstream: "very large scrollback ... can slow down performance
          # of the terminal and also use large amounts of RAM. Instead, consider
          # using scrollback_pager_history_size". So: a modest live buffer plus a
          # large pager history (kitty_mod+h, or kitty_scrollback_nvim on
          # kitty_mod+f below). Both live in kitty's heap; the pager history is
          # compact UTF-8, grows lazily in 1 MB steps, and the kitty-reclaim
          # timer below pushes its cold pages into zswap.
          scrollback_lines = scrollbackLines;
          scrollback_pager_history_size = 4096; # MB of RAM per window; kitty's max
          enable_audio_bell = true;
          bold_font = bold_font;
          italic_font = italic_font;
          bold_italic_font = BI_font;
          strip_trailing_spaces = "smart";
          enabled_layouts = "Splits";
          window_border_width = "4.0pt";
          inactive_border_color = "#5c5c5c";
          draw_minimal_borders = "yes";
          # WARN: Did not like change, might modify later.
          # window_margin_width = "1";
          # TODO: (med prio) setup later
          # tab_bar_style = "custom";
          allow_remote_control = "socket-only";
          listen_on = listenOn;
          disable_ligatures = "always";
          # PERF: input_delay/repaint_delay/sync_to_monitor are back at their
          # upstream defaults. The old 0/2/no trio targeted ~500 FPS with the
          # vblank cap removed, and every one of those frames is a wl_surface
          # commit Hyprland has to composite -- with blur, because the global
          # `opacity-all` window_rule (features/hm/wayland/hyprland.nix) makes
          # every window translucent, so no opaque-region cull applies. Measured
          # ~3 points of extra Hyprland CPU under a 200 lines/sec workload, on a
          # box whose Renoir iGPU already sits at 60-68% busy.
          #
          # input_delay = 0 was also the direct cause of the "erratic" redraws:
          # upstream warns it "might cause flicker in full screen programs that
          # redraw the entire screen on each loop, because kitty is so fast that
          # partial screen updates will be drawn" -- i.e. nvim.
          #
          # Kept: IME off is a real input-latency win with no cost here.
          "wayland_enable_ime" = "no";
          # only works in macos
          # background_blur = 1;
          # background_opacity = 0.9;
          cursor_shape_unfocused = "beam";
          # Plain blink, no easing. The easing function turns a 2-state toggle
          # into a continuous fade -- upstream: "turning on animations uses extra
          # power as it means the screen is redrawn multiple times per blink
          # interval" -- which redraws the focused window every repaint_delay for
          # the 15s cursor_stop_blinking_after window following each keystroke.
          cursor_blink_interval = "0.5";
          # cursor_trail's value is a dwell threshold in MILLISECONDS: the trail
          # only follows a cursor that held its position longer than this, which
          # is upstream's guard against trails firing "during UI updates in
          # complex applications". 1ms defeated the guard, so nvim/shell redraws
          # animated a trail (0.1-0.4s decay each). 40ms keeps the effect for
          # deliberate jumps and drops it for redraw churn.
          cursor_trail = 40;
        };
        # TODO: (low prio) need to set more keybindings
        # ref: https://sw.kovidgoyal.net/kitty/layouts/#the-splits-layout
        # NOTE: for todo: the most important keybindings are already setup.
        keybindings = {
          # ctrl+shift+\
          "kitty_mod+0x5c" = "launch --location=vsplit";
          # ctrl+shift+-
          "ctrl+shift+minus" = "launch --location=hsplit";
          # ctrl+ "+"
          "ctrl+equal" = "change_font_size all +0.5";
          # ctrl+ "-"
          "ctrl+minus" = "change_font_size all -1.0";
          # map ctrl+shift+v paste_from_clipboard
          # map ctrl+shift+c copy_to_clipboard

          # Replaces kitty's default kitty_mod+delete (clear_terminal reset
          # active), which wipes the pager history. See kittySoftReset.
          "kitty_mod+delete" = "launch --type=background ${kittySoftReset}/bin/kitty-soft-reset @active-kitty-window-id";
          # The old hard reset, moved off kitty_mod+delete, with a snapshot of
          # the full history taken first. See kittySnapshot.
          "kitty_mod+alt+delete" = "combine : launch --type=background --stdin-source=@ansi_screen_scrollback ${kittySnapshot}/bin/kitty-snapshot @active-kitty-window-id : clear_terminal reset active";

          "kitty_mod+f" = "kitty_scrollback_nvim";
          "kitty_mod+g" = "kitty_scrollback_nvim --config ksb_builtin_last_cmd_output";
          # "kitty_mod+j"
          # "kitty_mod+j"
        };

        extraConfig = ''
          action_alias kitty_scrollback_nvim kitten ${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py
          mouse_map ctrl+shift+right press ungrabbed combine : mouse_select_command_output : kitty_scrollback_nvim --config ksb_builtin_last_visited_cmd_output
          # PERF: disable ligatures
          font_features ${font} -liga
          font_features ${bold_font} -liga
          font_features ${italic_font} -liga
        '';
      };
    };

    # auto_reload_config is off (see programs.kitty.settings); instead, poke any
    # running kitty to re-read kitty.conf after HM rewrites it. SIGUSR1 is
    # kitty's documented reload signal. A reload is cheap and idempotent, so we
    # fire on every switch rather than only when kitty.conf actually changed.
    home.activation.reloadKitty =
      lib.hm.dag.entryAfter ["linkGeneration"] ''
        run ${pkgs.procps}/bin/pkill -USR1 -x kitty || true
      '';

    systemd.user.services.kitty-reclaim = {
      Unit.Description = "Push cold kitty scrollback pages into zswap.";
      Service = {
        Type = "oneshot";
        ExecStart = "${kittyReclaim}/bin/kitty-reclaim";
        Nice = 10;
      };
    };
    systemd.user.timers.kitty-reclaim = {
      Unit.Description = "Periodic proactive reclaim of kitty scopes.";
      Timer = {
        OnActiveSec = "5min";
        OnUnitActiveSec = "5min";
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}
