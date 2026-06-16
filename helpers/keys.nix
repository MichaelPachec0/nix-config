# Canonical SSH public keys, referenced across hosts/users instead of being
# copy-pasted. Each key is named by the YubiKey serial it lives on where known.
# Import with `keys = import ../../helpers/keys.nix;` (adjust depth) and use the named
# keys or the bundles below. See MAINTENANCE.md for context.
rec {
  m718 = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAICFSUN6IGskLmeq7ip+oTbYuE+WRLcbYGGGOAyH/ECWaAAAABHNzaDo= michael@nyx";
  m791 = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIHcU/epKhp9Ck0GoTNFP/H8X16B71tsTPgtCHzR0WTqxAAAABHNzaDo= michael@nyx";
  m828 = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIK9yS//bV3YX8oKyPPQsHCO1Nl1G8RLLAgIk8nRfWH4bAAAABHNzaDo= michael@nyx";
  m799 = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIMc+m32t4L/tBEVbPXdv4AgWils4tjP1TPpR/OWLqs2eAAAABHNzaDo= michael@nyx";
  m082 = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIAMd8o25peRqhUadrPW0Pjw+tsypjp2s4/qri4BxlxLvAAAABHNzaDo= michael@nyx";
  mUAY = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIAKEnIsOFEp1Lx9XwZRVN+iRKyCKRiy4U9kw1JWH1UAYAAAABHNzaDo= michael@nyx";
  mDIW = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIHMuXKaokH9SxXDGHAloLW9hyee+cjcfthdljpP96DiwAAAABHNzaDo= michael@nyx";
  thanatos = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIILWGChqPz8wzEO811YHGO222xgM60eF+oAMGgXqTEqqAAAABHNzaDo= thanatos";
  initrdKp = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAPjxSteZZH0yQeAzMT8VK7/XXa8s4Uqzy5ZWGMISah k@p";

  # All of michael's sk keys plus thanatos -- the full admin key set (kore, deploy).
  all = [m718 m791 m828 m799 m082 mUAY mDIW thanatos];
  # Subset present on the laptops / selene / nyx's michael user.
  laptops = [thanatos mDIW m082];
  # Keys allowed in the initrd SSH for boot unlock (kore, atlas).
  initrd = [initrdKp m718 m791 m828 mUAY];
}
