# AGENTS.md

glibc-only XBPS repo (`x86_64`). Binpkgs ship as `stable` release assets, never committed (see README migration note). musl twin: `z-repo-musl` (same layout, `--arch=x86_64-musl`, `void-musl-full`).

- Templates live in `SrDicov/z-packages` (`srcpkgs/`). Never commit `.xbps`/`*-repodata` (gitignored).
- `keys/zlinux-repo.pub` is the pubkey. Private key is `secrets.XBPS_PRIVATE_KEY` — never in git.
- Only logic: `.github/workflows/autobuild.yml` + `.github/scripts/check_outdated.py --arch=x86_64`. `check` (no container) diffs templates vs release asset names; `build` compiles only the gap, prunes to newest version per pkgname, signs, uploads changed assets only, deletes stale release assets.
- Manual runs: `packages="a b"` (empty = auto), `sync_only=true` (resign+republish), `force=true` (all). Daily `0 3 * * *` + `repository_dispatch` (`z-packages-update`).
- Speed: treeless clone, no full `xbps-install -yu` (uses `repo-ci`), `XBPS_PRESERVE_PKGS/CCACHE/MAKEJOBS`, cached `hostdir/sources` + `hostdir/ccache`.
- Symlinked `srcpkgs/<pkg>` dirs are subpackages — skipped, built via parent.
- Don't run `xbps-src` outside the Void containers.
