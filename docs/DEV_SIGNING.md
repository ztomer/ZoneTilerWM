# Local dev signing — keep the Accessibility grant across rebuilds

macOS keys the Accessibility (TCC) permission to an app's **code signature**, not its path.
Ad-hoc signing (`codesign -s -`) produces a *new* hash on every build, so each rebuild looks
like a different app and the grant you gave silently stops applying — the agent then shows its
"needs Accessibility" onboarding again even though you already granted it.

The fix is a **stable self-signed code-signing certificate**. Signing every build with the same
cert keeps the designated requirement constant, so the one grant sticks across rebuilds. This is
local-only; release builds use Developer ID + notarization (see `.github/workflows/release.yml`).

The build picks the identity up automatically: `build_package.sh` and `make app` sign with
`ZoneTilerWM Dev` when it exists in the keychain, and fall back to ad-hoc otherwise. Override the
name with `ZT_SIGN_ID=...`.

## One-time setup

Create the certificate (10-year self-signed, Code Signing EKU), import it into the login
keychain pre-authorized for `codesign`, and trust it for code signing:

```sh
cd /tmp
cat > ztdev.cnf <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[ dn ]
CN = ZoneTilerWM Dev
[ v3 ]
basicConstraints   = critical,CA:false
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout ztdev.key -out ztdev.crt -config ztdev.cnf

# NOTE: -legacy + SHA1 PBE — Apple's `security` can't import an OpenSSL 3 default p12.
openssl pkcs12 -export -legacy -inkey ztdev.key -in ztdev.crt -out ztdev.p12 \
  -name "ZoneTilerWM Dev" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
  -macalg sha1 -passout pass:ztdev

KC="$HOME/Library/Keychains/login.keychain-db"
security import ztdev.p12 -k "$KC" -P ztdev -T /usr/bin/codesign   # -T: codesign may use the key silently
security add-trusted-cert -p codeSign -k "$KC" ztdev.crt           # GUI: enter login password -> Update Settings
rm -f ztdev.key ztdev.crt ztdev.p12 ztdev.cnf

security find-identity -v -p codesigning   # should now list "ZoneTilerWM Dev"
```

`security find-identity` may annotate it `CSSMERR_TP_NOT_TRUSTED` — that's only about the
Gatekeeper trust chain (a self-signed cert has no CA). It is irrelevant here: TCC matches the
*designated requirement*, which is stable, and `codesign` signs with it fine.

## Build, install, grant — once

```sh
./build_package.sh
rm -rf /Applications/ZoneTilerWM.app
ditto /tmp/ZoneTilerWM/DerivedData/Build/Products/Release/ZoneTilerWM.app /Applications/ZoneTilerWM.app
open /Applications/ZoneTilerWM.app
```

Then grant once in **System Settings → Privacy & Security → Accessibility**. From now on
rebuilding + reinstalling keeps the grant — no re-granting.

## Sharing a build with someone else

Do **not** hand out a build signed with `ZoneTilerWM Dev` — that certificate lives only in your
keychain, so on another Mac the signature is unknown and the Accessibility grant can misbehave.
Use `./build_dist.sh`, which forces ad-hoc signing (no certificate dependency; ad-hoc TCC grants
work on any Mac). It prints the recipient's setup steps and leaves your local install untouched.
The build is not notarized, so the recipient clears Gatekeeper quarantine once
(`xattr -dr com.apple.quarantine /Applications/ZoneTilerWM.app`). It is also arm64-only.

## If the grant is misbehaving

Stale entries from earlier ad-hoc builds can shadow the real one. Wipe all entries for the
bundle id and grant fresh:

```sh
pkill -x ZoneTilerWM
tccutil reset Accessibility com.zaidenstein.ZoneTilerWM
```
