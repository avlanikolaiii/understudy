#!/bin/sh
# Creates (or imports) the code-signing identity Understudy is signed with, in its own keychain.
#   apps/mac/scripts/make-signing-identity.sh              → a new self-signed identity
#   apps/mac/scripts/make-signing-identity.sh id.p12       → import one (password in UNDERSTUDY_P12_PASSWORD)
#
# Why: macOS remembers privacy permissions (Screen Recording, Accessibility) by the app's signing
# identity. Ad-hoc builds get a new identity every build, so permissions are lost each time. A
# fixed certificate keeps them. It is self-signed (no Apple Developer Program), so the first open
# of a downloaded build still shows macOS's "unidentified developer" warning.
#
# Everything goes in apps/mac/.signing/ (git-ignored). The keychain is not added to your keychain
# list and nothing is trusted system-wide. Keep .signing/understudy.p12 safe: release builds must
# keep using the same identity, or people have to grant permissions again.
set -e
umask 077   # the private key and its passwords are readable by this user only
IMPORT=""
[ -n "$1" ] && IMPORT="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"   # resolve before changing directory
cd "$(dirname "$0")/.."
DIR=.signing
KEYCHAIN="$PWD/$DIR/understudy.keychain-db"
NAME="Understudy Open Source"
mkdir -p "$DIR"
chmod 700 "$DIR"
chmod 600 "$DIR"/* 2>/dev/null || true   # repairs files made before this was restricted
[ -f "$KEYCHAIN" ] && { echo "Already set up: $KEYCHAIN"; exit 0; }

if [ -n "$IMPORT" ]; then
  P12="$IMPORT"; P12_PASSWORD="${UNDERSTUDY_P12_PASSWORD:?set UNDERSTUDY_P12_PASSWORD}"
else
  P12="$DIR/understudy.p12"; P12_PASSWORD="$(openssl rand -hex 16)"
  TMP="$(mktemp -d)"
  cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
  openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$P12" -passout "pass:$P12_PASSWORD" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
  rm -rf "$TMP"
  printf %s "$P12_PASSWORD" > "$DIR/understudy.p12.password"
fi

openssl rand -hex 16 > "$DIR/keychain-password"
security create-keychain -p "$(cat "$DIR/keychain-password")" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # no auto-lock
security unlock-keychain -p "$(cat "$DIR/keychain-password")" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$(cat "$DIR/keychain-password")" "$KEYCHAIN" >/dev/null
echo "Signing identity ready: \"$NAME\" in $KEYCHAIN"
