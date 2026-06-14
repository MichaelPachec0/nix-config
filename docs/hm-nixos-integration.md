# Integrating home-manager as a NixOS module (keeping `home-manager switch`)

Goal: run the same home-manager (HM) config two ways, from a single source of
truth:

1. Standalone: `home-manager switch --flake .#michael-<host>` (the `hmsf` alias).
2. Integrated: built and activated as part of `nixos-rebuild switch`.

Decision: integrated mode uses `home-manager.useGlobalPkgs = true` (HM reuses the
system `pkgs` instead of evaluating its own nixpkgs).

## Current state (before this work)

Standalone path (works): `homeConfigurations.*` in `flake.nix` via `mkHomeConfig`.
Each user composed, in order:

- `overlays.unstable.homeManagerDesktop` -- overlay modules + `inputs.nixneovim.nixosModules.homeManager`
- `./hm/home.nix`
- `inputs.hyprland.homeManagerModules.default`
- a per-host module (`./hm/home-nyx.nix`, etc.)
- `extraSpecialArgs = { inherit inputs outputs; }`
- its own `pkgs` (overlays applied inside HM via `mkOverlayModules`)

NixOS-module path (was non-functional): `nixos/aphrodite/apple.nix` imported the HM
NixOS module and `extras.nix` set `useGlobalPkgs`/`useUserPackages`, but no user's
home config was actually defined. `nixos/thanatos/extras.nix` defined
`home-manager.users.michael` but was commented out of the flake. The helper
scaffolding in `helpers/externalModules.nix` and `overlays.*.homeManager` was
unused. Net: no host ran a working integrated HM config.

## Blockers and how they are resolved

A. Module-set divergence. `home-manager.users.michael = ./hm/home.nix` imports only
   `home.nix`; the standalone path additionally pulls in the hyprland HM module, the
   nixneovim HM module, and the per-host module. Resolved by a single shared module
   builder, `helpers/home.nix:mkHomeModules`, used by both paths.

B. Missing `extraSpecialArgs`. `home.nix` needs `inputs`. The integrated path now
   sets `home-manager.extraSpecialArgs = { inherit inputs outputs; standalone = false; }`.

C. `useGlobalPkgs` vs in-HM overlays (the main one). With `useGlobalPkgs = true` HM
   reuses the system `pkgs` and forbids `nixpkgs.*` inside HM modules. But the HM
   desktop overlay set is a superset of the NixOS desktop set: it adds
   `vimPluginsOverlayList` + `lspServers` (+ the claude-code overlay from `home.nix`)
   that `nixosDesktop` does not apply. The custom `pkgs.vimPlugins.*`,
   `pkgs.emmet-language-server`, `pkgs.nixd`, `pkgs.claude-code`, etc. that the HM
   config depends on would otherwise be missing.

   Resolved by hoisting that delta onto the system. `helpers/overlays.nix` exports
   `unstable.hmIntegrationOverlays = vimPluginsOverlayList ++ lspServers ++ [claude-code]`,
   and `features/nixos/home` adds it to the system `nixpkgs.overlays`.

D. `nixpkgs.*` set inside HM modules. Three spots set them:
   - `hm/home.nix` -> `nixpkgs.overlays = [claude-code]`
   - `features/hm/common/default.nix` -> `nixpkgs.config = { allowUnfree = ...; }`
   - `features/hm/wayland/default.nix` -> `nixpkgs.overlays = []` (dead, all commented)

   The first two are now guarded with `lib.mkIf standalone { ... }`, so they vanish
   (no definition) when integrated. The dead one in `wayland` was removed. The
   system already sets `nixpkgs.config.allowUnfree = true` (`nixos/nyx/configuration.nix`).

E. Minor: `nix.*` in `home.nix` is now `lib.mkIf standalone` -- the system owns nix
   config when integrated. `caches.nix` keeps setting `nix.settings.substituters`,
   but note those in the per-user nix.conf are ignored for non-trusted users; for
   integrated hosts the caches should live in the system `nix.settings` (follow-up).
   The HM `report-changes` activation still runs `nvd diff`; it is redundant with the
   system-level `nvd diff` but harmless (follow-up: gate it on `standalone`).

## The `standalone` flag

A module argument `standalone` (default `true`) threads through HM modules via
`extraSpecialArgs`:

- standalone path: does not set it -> defaults to `true` -> overlays + `nixpkgs.config`
  are applied inside HM, exactly as before.
- integrated path: sets `standalone = false` -> those `nixpkgs.*` definitions disappear;
  the system provides pkgs + overlays.

## Files

New:
- `helpers/home.nix` -- `mkHomeModules { entry, perHost ? [], standalone ? true, desktop ? true, channel ? "unstable" }`,
  the single source of truth for the per-user module list.
- `features/nixos/home/default.nix` -- reusable NixOS module. Imports the HM NixOS
  module, sets `useGlobalPkgs`/`useUserPackages`/`extraSpecialArgs`, hoists
  `hmIntegrationOverlays`, and wires `home-manager.users.<user>` from `mkHomeModules`.
  Gated behind `local.hm.enable`; options: `user`, `entry`, `perHost`, `desktop`.

Changed:
- `helpers/overlays.nix` -- exports `unstable.hmIntegrationOverlays`.
- `hm/home.nix` -- `standalone ? true` arg; `nixpkgs.overlays` and `nix` guarded by `mkIf standalone`.
- `features/hm/common/default.nix` -- `standalone ? true` arg; `nixpkgs.config` guarded by `mkIf standalone`.
- `features/hm/wayland/default.nix` -- removed dead empty `nixpkgs.overlays`.
- `flake.nix` -- `homeModules = import ./helpers/home.nix`; `michael-nyx` and
  `michael-thanatos` now built from `mkHomeModules` (behavior-preserving).
- `nixos/thanatos/extras.nix` -- rewritten as the integrated pilot (enables `local.hm`).

## How to test the pilot (thanatos)

The integrated pilot is one line away. In `flake.nix`, the thanatos module list,
uncomment:

    # ./nixos/thanatos/extras.nix

Then, BEFORE switching:

    nix flake check
    nix build .#nixosConfigurations.thanatos.config.system.build.toplevel
    nix build .#homeConfigurations.michael-thanatos.activationPackage

Both must evaluate. Then `nixos-rebuild build --flake .#thanatos`. The standalone
path keeps working independently the whole time
(`home-manager switch --flake .#michael-thanatos`).

If something fails, comment that one line back out; nothing else depends on it.

## Rollout / follow-ups

- After thanatos is verified: enable on nyx and aphrodite. For aphrodite, drop the
  now-redundant `inputs.home-manager.nixosModules.home-manager` import in `apple.nix`
  and the `useGlobalPkgs`/`useUserPackages` lines in its `extras.nix`
  (`features/nixos/home` owns them).
- Servers (sysadmin, stable channel) need a stable variant of the overlay hoist and
  a non-desktop module set; deferred.
- Delete the dead scaffolding (`helpers/externalModules.nix`, `overlays.*.homeManager`)
  once the new path is proven.
- Add the integrated builds to CI (`.github/workflows/pr.yaml`); `home-manager-check.sh`
  only checks `homeConfigurations`.
- Decide whether to gate `report-changes` on `standalone` and move cache substituters
  to system `nix.settings`.
