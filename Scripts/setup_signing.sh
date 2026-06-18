#!/usr/bin/env bash
#
# One-time: create a stable self-signed code-signing identity so macOS sees
# every local build as the SAME app. Without this, ad-hoc signing changes the
# code hash on every build and macOS forgets the Accessibility/Microphone
# grants each time (you'd have to re-authorize after every rebuild).
#
# Run once: ./Scripts/setup_signing.sh   (you may get one keychain prompt — Allow it)
#
set -euo pipefail

CERT="WhisperDict Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT"; then
    echo "OK: identity '$CERT' already exists."
    exit 0
fi

TMP="$(mktemp -d)"
cat > "$TMP/cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CERT
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "-> Generating self-signed code-signing certificate"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/cnf" >/dev/null 2>&1

openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:temp -name "$CERT" >/dev/null 2>&1

echo "-> Importing into login keychain (authorizing codesign to use it)"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P temp -T /usr/bin/codesign >/dev/null

rm -rf "$TMP"
echo ""
echo "OK: created '$CERT'. build.sh will now sign with it."
