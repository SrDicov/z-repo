#!/bin/bash
# Idempotent publish for z-repo autobuild: prune old versions, sign,
# index, upload changed assets, delete stale ones.
# Safe on empty dirs and safe to re-run (rescue path on build failure).
# Env: ARCH, REPO_TAG, GH_REPO, XBPS_PRIVATE_KEY, SIGNED_BY (optional).
set -e
set -o pipefail

DIR="${1:?usage: publish.sh <binpkgs dir>}"
cd "$DIR"
shopt -s nullglob
pkgs=( *.xbps )
if [ "${#pkgs[@]}" -eq 0 ]; then
  echo "no packages in $DIR, nothing to publish"
  exit 0
fi
: "${SIGNED_BY:=Z Linux Core <SrDicov@gmail.com>}"

echo "$XBPS_PRIVATE_KEY" > /tmp/rsa.pem
chmod 600 /tmp/rsa.pem
# keep only the newest <pkg>-<ver>_<rev> per pkgname: no duplicates
ARCH="$ARCH" python3 - <<'EOF'
import os, re
from collections import defaultdict
arch = os.environ["ARCH"]
pkgs = defaultdict(list)
for f in os.listdir("."):
    m = re.match(r"(.+)-([^-]+)_([^.]+)\.%s\.xbps$" % re.escape(arch), f)
    if m:
        pkgs[m.group(1)].append((m.group(2), m.group(3), f))
def vkey(v):
    return tuple(int(p) if p.isdigit() else p for p in re.split(r"[.]", v))
for name, vers in pkgs.items():
    vers.sort(key=lambda t: (vkey(t[0]), t[1]))
    for _, _, f in vers[:-1]:
        for ext in ("", ".sig2", ".sig"):
            try:
                os.remove(f + ext)
            except FileNotFoundError:
                pass
        print("pruned", f)
EOF
# every publication re-signs with the current key: a .sig2 left over
# from a rotated key would keep packages signed by the retired key
rm -f ./*.sig2
xbps-rindex --sign-pkg --privkey /tmp/rsa.pem ./*.xbps
xbps-rindex -a *.xbps
xbps-rindex --sign --signedby "$SIGNED_BY" --privkey /tmp/rsa.pem .
rm -f /tmp/rsa.pem

repodata="$ARCH-repodata"
gh release view "$REPO_TAG" >/dev/null 2>&1 || \
  gh release create "$REPO_TAG" --title "Z Linux $ARCH repo" \
    --notes "Rolling XBPS repo for $ARCH."
# drop stale assets. An .xbps and its .sig2 are one logical asset:
# build the expected set from the local files and delete every remote
# .xbps/.sig2 asset absent from it, so a signature can never outlive
# its package (or vice versa).
expected=$(mktemp)
{
  printf '%s\n' *.xbps
  printf '%s\n' *.xbps.sig2
} | sort -u > "$expected"
stale=0
while IFS= read -r a; do
  case "$a" in *.xbps*) ;; *) continue ;; esac
  grep -Fxq -- "$a" "$expected" && continue
  for try in 1 2 3; do
    if gh release delete-asset "$REPO_TAG" "$a" -y; then
      echo "deleted stale asset $a"
      break
    elif [ "$try" -lt 3 ]; then
      echo "delete $a failed (try $try), retrying" >&2
      sleep 3
    else
      echo "FAILED to delete stale asset $a" >&2
      stale=1
    fi
  done
done < <(gh api "repos/$GH_REPO/releases/tags/$REPO_TAG" \
  --paginate --jq '.assets[].name' | sort -u)
rm -f "$expected"
[ "$stale" -eq 0 ] || exit 1
# upload new/changed assets (same name+size = already there).
# NOTE: RSA sigs are fixed-size, so after a key rotation same-size sigs
# would look current: RESIGN=true forces upload of everything.
for f in "$repodata" *.xbps*; do
  [ -e "$f" ] || continue
  n=$(basename "$f"); s=$(stat -c%s "$f")
  rs=$(gh release view "$REPO_TAG" --json assets \
    --jq ".assets[] | select(.name==\"$n\") | .size" 2>/dev/null || true)
  if [ "${RESIGN:-false}" != "true" ] && [ "$rs" = "$s" ]; then
    echo "up to date: $n"
  else
    gh release upload "$REPO_TAG" --clobber "$f"
  fi
done
