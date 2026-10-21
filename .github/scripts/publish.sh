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

# publish the public key both raw (PEM) and in the exact plist format
# xbps externalizes to /var/db/xbps/keys/<fingerprint>.plist (format
# byte-identical to an xbps import in a Void container), so users can
# pre-import without an interactive prompt: xbps names that file after
# the MD5 SSH fingerprint with colons but WITHOUT the "MD5:" prefix.
# curl -O <release URL>/$fp.plist
# cp $fp.plist /var/db/xbps/keys/
openssl pkey -in /tmp/rsa.pem -pubout -out /tmp/pub.pem
kh=$(ssh-keygen -i -m PKCS8 -f /tmp/pub.pem | ssh-keygen -lf - -E md5)
bits=${kh%% *}
# ssh-keygen prints "bits fp comment": the fingerprint is field 2,
# "MD5:xx:...".  Field 3 is the comment ("no" here), not the fingerprint.
fp=${kh#* };
fp=${fp%% *}
fp=${fp#MD5:}
[ -n "$bits" ] && [ -n "$fp" ] || { echo "failed to derive pubkey fingerprint" >&2; exit 1; }
esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
{
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0">' \
    '<dict>'
  printf '\t<key>public-key</key>\n\t<data>%s</data>\n' "$(base64 -w0 /tmp/pub.pem)"
  printf '\t<key>public-key-size</key>\n\t<integer>%s</integer>\n' "$bits"
  printf '\t<key>signature-by</key>\n\t<string>%s</string>\n' "$(esc "$SIGNED_BY")"
  printf '%s\n' '</dict>' '</plist>'
} > "$fp.plist"
cp /tmp/pub.pem zlinux-repo.pub
rm -f /tmp/rsa.pem /tmp/pub.pem

repodata="$ARCH-repodata"
gh release view "$REPO_TAG" >/dev/null 2>&1 || \
  gh release create "$REPO_TAG" --title "Z Linux $ARCH repo" \
    --notes "Rolling XBPS repo for $ARCH."
# drop stale assets, but only what can be proven superseded. The
# expected set reflects the seed, and a partial seed is exactly how the
# release lost hyprsunset and hyprland-preview-share-picker once. So:
# - a package not built this run keeps ALL its remote assets;
# - a locally present package's own old assets are superseded;
# - the key plist (any fingerprint), the pub and the repodata are
#   regenerated below, so their old names can always go;
# - everything else is kept, loudly, not deleted blind.
expected=$(mktemp)
{
  printf '%s\n' *.xbps
  printf '%s\n' *.xbps.sig2
  printf '%s\n' "$fp.plist" zlinux-repo.pub "$repodata"
} | sort -u > "$expected"
# pkgver without arch and revision -> pkgname, same last-dash split the
# prune step above uses
pkgname() {
  case "$1" in
    *.xbps.sig2) b=${1%.xbps.sig2} ;;
    *.xbps.sig)  b=${1%.xbps.sig} ;;
    *.xbps)      b=${1%.xbps} ;;
    *) return 1 ;;
  esac
  b=${b%.*}
  b=${b%_*}
  printf '%s\n' "${b%-*}"
}
localpkgs=$(mktemp)
for f in *.xbps; do pkgname "$f"; done | sort -u > "$localpkgs"
stale=0
kept=0
while IFS= read -r a; do
  case "$a" in "") continue ;; esac
  grep -Fxq -- "$a" "$expected" && continue
  del=no
  case "$a" in
    *.plist | zlinux-repo.pub | *-repodata) del=yes ;;
    *.xbps.sig2 | *.xbps.sig)
      if grep -Fxq -- "$(pkgname "$a")" "$localpkgs"; then del=yes; fi
      ;;
    *.xbps)
      if grep -Fxq -- "$(pkgname "$a")" "$localpkgs"; then del=yes; fi
      ;;
  esac
  if [ "$del" = no ]; then
    echo "keeping asset not proven stale (package not built this run): $a"
    kept=$((kept + 1))
    continue
  fi
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
rm -f "$expected" "$localpkgs"
if [ "$kept" -gt 0 ]; then
  echo "::warning::$kept release asset(s) kept unverified; their package was not in this run's set (seed incomplete?)"
fi
[ "$stale" -eq 0 ] || exit 1
# upload new/changed assets. Size is not identity: a rebuilt package
# can keep the exact byte count while its content changed, and pairing
# the old .xbps with the fresh .sig2 leaves an invalid signature.
# Compare the sha256 digest the GitHub assets API exposes for every
# asset ("sha256:<hash>", via the REST API; gh release view does not)
# against the local file: one criterion for .xbps, .sig2 and the rest.
assets=$(mktemp)
gh api "repos/$GH_REPO/releases/tags/$REPO_TAG" --paginate \
  --jq '.assets[] | .digest + " " + .name' > "$assets"
for f in "$fp.plist" zlinux-repo.pub "$repodata" *.xbps*; do
  [ -e "$f" ] || continue
  n=$(basename "$f")
  ld="sha256:$(sha256sum "$f" | awk '{print $1}')"
  rd=$(awk -v n="$n" '$2 == n { print $1 }' "$assets")
  if [ "$ld" = "$rd" ]; then
    echo "up to date: $n"
  else
    gh release upload "$REPO_TAG" --clobber "$f"
  fi
done
rm -f "$assets"
