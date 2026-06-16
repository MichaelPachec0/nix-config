#!/usr/bin/env bash

# NOTE: This grabs all the users in the flake.
# WARN: Since this does not depend on a flake.lock, this operation needs to be marked impure.
# Since this only grabs a list of users, its inconsequential.
USERS="$(nix eval --expr "builtins.attrNames (builtins.getFlake \"\${builtins.toString ./.}\").outputs.homeConfigurations" --impure)"
OIFS=$IFS
USERS="${USERS:2:-2}"
IFS=' ' read -r -a USERS <<<"$USERS"
for USER in "${USERS[@]}"; do
  echo "HOME-MANAGER: CHECKING $USER"
  # NOTE: use this for now to evaluate, there might be a better way to do this in the future.
  # Also make sure to remove the quotes, as they were not removed earlier.
  nix derivation show ".#homeConfigurations.${USER:1:-1}.activationPackage"
done
IFS=$OIFS
