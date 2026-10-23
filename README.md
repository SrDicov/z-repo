# z-repo — Z Linux Binary Repository (glibc)

Repositorio binario XBPS para Z Linux (solo **glibc `x86_64`**), publicado
como **assets del release `stable`**.
El gemelo musl previsto es `z-repo-musl` (misma estructura, `x86_64-musl`).

- **Repo XBPS:** `https://github.com/SrDicov/z-repo/releases/download/stable`
- **Source repo (plantillas):** `https://github.com/SrDicov/z-packages` (`srcpkgs/`)
- **Llave pública:** `keys/zlinux-repo.pub` (vía Pages)

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

## Instalación

El asset con la clave lleva el fingerprint con **puntos** (GitHub no admite
`:` en nombres de asset), pero xbps indexa las claves por el **nombre del
fichero** y espera dos puntos. Hay que renombrarla al copiarla:

```sh
fp=02:16:21:e8:80:43:b6:16:d4:63:13:e5:5d:e1:32:b7
mkdir -p /var/db/xbps/keys /etc/xbps.d
curl -fsSL -o "/var/db/xbps/keys/$fp.plist" \
  "https://github.com/SrDicov/z-repo/releases/download/stable/${fp//:/.}.plist"
echo "repository=https://github.com/SrDicov/z-repo/releases/download/stable" \
  > /etc/xbps.d/10-zrepo.conf
xbps-install -S
```
