# z-repo — Z Linux Binary Repository (glibc)

Repositorio binario XBPS para Z Linux (solo **glibc `x86_64`**), publicado
como **assets del release `stable`** (modo repo-neko: nada en git).
El gemelo musl previsto es `z-repo-musl` (misma estructura, `x86_64-musl`).

- **Repo XBPS:** `https://github.com/SrDicov/z-repo/releases/download/stable`
- **Source repo (plantillas):** `https://github.com/SrDicov/z-packages` (`srcpkgs/`)
- **Llave pública:** `keys/zlinux-repo.pub` (vía Pages)

## Uso en mklive.sh
```bash
mkdir -p "$ROOTFS/var/db/xbps/keys"
curl -sL https://srdicov.github.io/z-repo/keys/zlinux-repo.pub -o "$ROOTFS/var/db/xbps/keys/zlinux-repo.pub"

sudo ./mklive.sh \
  -r https://github.com/SrDicov/z-repo/releases/download/stable \
  -r https://repo-default.voidlinux.org/current \
  -t x86_64-YYYYMMDD-labwc
```

## Workflow
`autobuild.yml`: `check` (ligero, sin contenedor) compara cada template
`srcpkgs/` con los assets del release (`check_outdated.py --arch=x86_64`,
sin descargar); `build` compila solo lo nuevo/desactualizado y publica.
Sin duplicados: antes de firmar se conserva solo la versión más nueva de
cada `pkgname` y se borran del release los assets viejos.

Disparadores: diario (`0 3 * * *`), push a `.github/**`, `keys/` o docs,
`repository_dispatch` (`z-packages-update`) y manual con `packages=` (coma/espacio, vacío =
auto-detectar), `sync_only=true` (solo re-firmar `repodata` y republicar)
o `force=true` (todo).

## Caché / velocidad
Treeless shallow clone, sin `xbps-install -yu` completo (mirror `repo-ci`),
`XBPS_PRESERVE_PKGS + CCACHE + MAKEJOBS=$(nproc)` y caché de
`hostdir/sources` + `hostdir/ccache` entre runs.

## Firma
Paquetes e índices firmados con RSA (`xbps-rindex --sign`). La llave privada
vive en `secrets.XBPS_PRIVATE_KEY` — nunca en git.

## Historial
Los `.xbps` vivían commiteados en `x86_64/`; desde 2026-09-26 se publican
como assets del release `stable` (ver releases). El historial git conserva
los binarios viejos.
