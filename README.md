# z-repo — Z Linux Binary Repository

Repositorio binario XBPS para Z Linux, servido vía **GitHub Pages**.

- **URL Pages:** `https://srdicov.github.io/z-repo/`
- **Source repo:** `https://github.com/SrDicov/z-packages` (plantillas `srcpkgs/`)
- **Llave pública:** `keys/zlinux-repo.pub`

## Estructura
```
z-repo/
├── keys/zlinux-repo.pub
├── x86_64/              # glibc x86_64 (Intel/AMD)
│   ├── x86_64-repodata     # índice (firma embebida vía xbps-rindex --sign)
│   └── *.xbps + *.xbps.sig2
├── x86_64-musl/         # musl x86_64
│   ├── x86_64-musl-repodata
│   └── ...
└── .github/workflows/autobuild.yml
```

## Uso en mklive.sh
```bash
mkdir -p "$ROOTFS/var/db/xbps/keys"
curl -sL https://srdicov.github.io/z-repo/keys/zlinux-repo.pub -o "$ROOTFS/var/db/xbps/keys/zlinux-repo.pub"

sudo ./mklive.sh \
  -r https://github.com/SrDicov/z-repo/releases/download/librewolf-x86_64 \
  -r https://srdicov.github.io/z-repo/x86_64 \
  -r https://repo-default.voidlinux.org/current \
  -t x86_64-YYYYMMDD-labwc
```

> `librewolf` (>100MB, GitHub no lo admite en git) vive en un repo
> aparte servido como release asset; el resto está en `x86_64/`.

## Workflow
El workflow `autobuild.yml` (en este repo) clona `SrDicov/z-packages` y publica aquí. Se dispara manualmente, por push y cada hora. Para no recompilar lo que ya está publicado:
- El job `check` (ligero, sin contenedor) compara cada template `srcpkgs/` con los binpkgs publicados (`.github/scripts/check_outdated.py`): solo pasan a build los paquetes nuevos o desactualizados. Los servidos vía releases (`RELEASE_PKGS`, hoy `librewolf`) se comparan contra los assets del release.
- Cada arch compila solo su lista, en paralelo (`build-glibc` / `build-musl`).
- Un paquete que falle marca el job en rojo (el siguiente run lo reintenta solo).
- `workflow_dispatch` admite `force=true` para recompilarlo todo.

## Firma
Paquetes e índices firmados con RSA (`xbps-rindex --sign`). La llave privada vive en `secrets.XBPS_PRIVATE_KEY` — nunca en git.

