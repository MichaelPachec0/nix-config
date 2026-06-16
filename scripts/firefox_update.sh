#!/usr/bin/env bash

FXJSON=$(curl -sL https://product-details.mozilla.org/1.0/firefox_versions.json)

version=$(
	 echo "$FXJSON" |
		jq '.FIREFOX_DEVEDITION' |
    # TODO: move to sed?
		tr -d \"
)
if [[ $version ]]; then
	echo "Got Firefox version ${version}"
	# URL="https://archive.mozilla.org/pub/devedition/releases/${version}/linux-x86_64/en-US/firefox-${version}.tar.bz2"
	URL="https://archive.mozilla.org/pub/devedition/releases/${version}/linux-x86_64/en-US/firefox-${version}.tar.xz"
  SHA256=$(nix-prefetch-url "$URL" --type sha256)
  SRIHASH=$(nix hash to-sri --type sha256 "$SHA256")
  printf "ouput: \nversion = \"%s\";\nsha256 = \"%s\";\n" "$version" "$SHA256"
  echo  "SRI: ${SRIHASH}"
else
  echo "ERROR: NO FIREFOX VERSION FOUND!"
  echo "DEBUG: JSON:"
  echo "$FXJSON"

fi
