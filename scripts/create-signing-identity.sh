#!/usr/bin/env bash
# One-time setup: create a self-signed "GameBridge Dev" code-signing identity
# in the current user's login keychain. Debug builds use this identity
# (see project.yml) so the cdhash stays stable across rebuilds and TCC grants
# (Accessibility etc.) don't silently disappear.
#
# Safe to re-run — exits early if the identity already exists.

set -euo pipefail

IDENTITY_NAME="GameBridge Dev"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$IDENTITY_NAME" "$LOGIN_KEYCHAIN" >/dev/null 2>&1; then
    echo "'$IDENTITY_NAME' already in login keychain."
    codesign -dv --verbose=1 /bin/ls >/dev/null 2>&1 || true
    exit 0
fi

TMP="$(mktemp -d -t gamebridge-signing)"
trap 'rm -rf "$TMP"' EXIT

# 10-year self-signed cert with codeSigning EKU.
openssl req -x509 -newkey rsa:2048 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes \
    -subj "/CN=$IDENTITY_NAME/O=GameBridge/C=US" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" >/dev/null 2>&1

# openssl 3.x defaults to PBES2/SHA256 for PKCS12 which macOS Security
# can't parse. `-legacy` forces PBES1/SHA1. macOS also rejects empty PKCS12
# passphrases, so use a throwaway one.
openssl pkcs12 -export -legacy \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY_NAME" \
    -out "$TMP/bundle.p12" -passout pass:gamebridge >/dev/null 2>&1

# -A lets codesign use the key without prompting on every rebuild.
security import "$TMP/bundle.p12" \
    -k "$LOGIN_KEYCHAIN" \
    -P "gamebridge" \
    -A

echo
echo "Imported identity '$IDENTITY_NAME' into login keychain."
echo "You can now rebuild GameBridge; project.yml already references it."
