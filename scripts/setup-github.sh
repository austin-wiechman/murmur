#!/bin/zsh
# One-time setup for publishing releases (see RELEASING.md): creates the app and Homebrew tap repositories and stores the release
# secrets. Each secret goes from its generator straight to `gh secret set` and is never printed.
# Rerunning leaves existing repositories and secrets alone.
set -euo pipefail
cd "${0:A:h}/.."

if ! gh auth status 2>&1 | grep -q "'workflow'"; then
    echo "gh needs the workflow scope to push .github/workflows. Run: gh auth refresh -s workflow" >&2
    exit 1
fi

owner=$(gh api user --jq .login)
repo=$owner/murmur
tap=$owner/homebrew-tap
identity="Murmur Release Signing"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

has_secret() { gh secret list -R "$repo" --json name --jq '.[].name' | grep -qx "$1" }

gh repo view "$repo" >/dev/null 2>&1 || gh repo create "$repo" --public --source . --remote origin \
    --description "Local-first push-to-talk dictation for macOS"
gh repo view "$tap" >/dev/null 2>&1 || gh repo create "$tap" --public --add-readme \
    --description "Homebrew tap for apps by $owner"
# release-please opens its release pull request with the workflow token.
gh api -X PUT "repos/$repo/actions/permissions/workflow" -f default_workflow_permissions=read \
    -F can_approve_pull_request_reviews=true

# macOS ties Accessibility and Microphone grants to the signing certificate, so every release must use
# this one. The login keychain keeps the only other copy. /usr/bin/openssl is LibreSSL: OpenSSL 3
# writes a .p12 that `security import` rejects.
if ! has_secret SIGNING_CERT_P12; then
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$identity" \
        -keyout "$work/signing.key" -out "$work/signing.crt" \
        -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
        -addext "basicConstraints=critical,CA:false" 2>/dev/null
    password=$(/usr/bin/openssl rand -base64 24)
    /usr/bin/openssl pkcs12 -export -inkey "$work/signing.key" -in "$work/signing.crt" -name "$identity" \
        -passout pass:"$password" -out "$work/signing.p12"
    security import "$work/signing.p12" -k ~/Library/Keychains/login.keychain-db -P "$password" \
        -T /usr/bin/codesign >/dev/null
    base64 -i "$work/signing.p12" | gh secret set SIGNING_CERT_P12 -R "$repo"
    print -rn -- "$password" | gh secret set SIGNING_CERT_PASSWORD -R "$repo"
fi

if ! has_secret SPARKLE_ED_PRIVATE_KEY; then
    swift package resolve >/dev/null
    keys=.build/artifacts/sparkle/Sparkle/bin/generate_keys
    public=$($keys --account murmur -p)
    if [[ "$public" != "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)" ]]; then
        echo "The murmur Sparkle key in the keychain doesn't match SUPublicEDKey in Info.plist." >&2
        exit 1
    fi
    $keys --account murmur -x "$work/sparkle.key" >/dev/null
    gh secret set SPARKLE_ED_PRIVATE_KEY -R "$repo" < "$work/sparkle.key"
fi

if ! has_secret TAP_DEPLOY_KEY; then
    ssh-keygen -t ed25519 -N "" -C "murmur releases" -f "$work/tap" -q
    gh repo deploy-key add "$work/tap.pub" -R "$tap" --allow-write --title "murmur releases"
    gh secret set TAP_DEPLOY_KEY -R "$repo" < "$work/tap"
fi

echo "Set up $repo and $tap."
