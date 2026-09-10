#!/usr/bin/env python3
"""Decide which z-packages templates need (re)building per arch.

Static template parsing only (never source them). For each real template
dir in srcpkgs/ (symlinked dirs are built via their parent, like the
build loop does), the main binpkg <pkg>-<ver>_<rev>.<arch>.xbps must be
present in the published file list. Parent-binpkg presence implies its
subpackages (same version, built in the same xbps-src run; template-only
changes require a revision bump per repo rules).

musl exclusion uses the standard idiom: a `broken=` assignment guarded by
XBPS_TARGET_LIBC = musl.

Usage: check_outdated.py <srcpkgs dir> <x86_64 list> <musl list>
       [pkgname=release-asset-list ...]
Prints `glibc:<pkgs>` / `musl:<pkgs>` lines (empty = all current).
Packages shipped via GitHub releases (too big for git, e.g. librewolf)
are compared against their release asset list instead of the repo tree.
"""

import fnmatch
import os
import re
import sys


def parse_template(path):
    """Extract pkgname/version/revision/archs with shell-safe static rules:
    plain VAR="value" assignments, no substitution (enforced by repo rules).
    """
    vals = {}
    # Void style is usually unquoted (pkgname=foo); accept both forms.
    # First occurrence wins: top-level assignments precede subpackage
    # functions and conditionals that reuse the same names.
    assign = re.compile(r'^(pkgname|version|revision|archs)="?([^"\s]*)"?\s*$')
    with open(path) as fh:
        for line in fh:
            m = assign.match(line.strip())
            if m and m.group(1) not in vals:
                vals[m.group(1)] = m.group(2)
    return vals


def musl_broken(path):
    """True if the template sets broken= under a musl guard."""
    guard = re.compile(r'XBPS_TARGET_LIBC"\s*=\s*"musl"')
    with open(path) as fh:
        recent_guard = False
        window = []
        for line in fh:
            s = line.strip()
            window.append(s)
            window = window[-6:]
            if guard.search(s):
                recent_guard = True
            if s.startswith("broken=") and (
                recent_guard or "musl" in " ".join(window)
            ):
                return True
            if s == "fi":
                recent_guard = False
    return False


def arch_wanted(archs, target):
    if not archs:
        return True
    return any(fnmatch.fnmatchcase(target, pat) for pat in archs.split())


def main():
    args = sys.argv[1:]
    srcpkgs, glibc_list, musl_list = args[:3]
    release_lists = {}
    for extra in args[3:]:
        pkg, path = extra.split("=", 1)
        with open(path) as fh:
            release_lists[pkg] = {
                line.strip() for line in fh if line.strip().endswith(".xbps")
            }
    published = {}
    for arch, listfile in (("x86_64", glibc_list), ("x86_64-musl", musl_list)):
        with open(listfile) as fh:
            published[arch] = {
                line.strip() for line in fh if line.strip().endswith(".xbps")
            }
    need = {"x86_64": [], "x86_64-musl": []}
    for entry in sorted(os.listdir(srcpkgs)):
        tpldir = os.path.join(srcpkgs, entry)
        if not os.path.isdir(tpldir) or os.path.islink(tpldir):
            continue
        tpl = os.path.join(tpldir, "template")
        if not os.path.isfile(tpl):
            continue
        vals = parse_template(tpl)
        if not all(k in vals for k in ("pkgname", "version", "revision")):
            print(f"WARN: {entry}: cannot parse version, forcing build")
            need["x86_64"].append(entry)
            need["x86_64-musl"].append(entry)
            continue
        is_musl_broken = musl_broken(tpl)
        for arch in ("x86_64", "x86_64-musl"):
            if arch == "x86_64-musl" and is_musl_broken:
                continue
            if not arch_wanted(vals.get("archs", ""), arch):
                continue
            want = (
                f"{vals['pkgname']}-{vals['version']}_"
                f"{vals['revision']}.{arch}.xbps"
            )
            pool = release_lists.get(entry, published[arch])
            if want not in pool:
                need[arch].append(entry)
    for arch in ("x86_64", "x86_64-musl"):
        print(f"{'glibc' if arch == 'x86_64' else 'musl'}:{' '.join(need[arch])}")


if __name__ == "__main__":
    main()
