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
  -r https://srdicov.github.io/z-repo/x86_64 \
  -r https://repo-default.voidlinux.org/current \
  -t x86_64-YYYYMMDD-labwc
```

## Workflow
El workflow `autobuild.yml` (en este repo) clona `SrDicov/z-packages`, compila solo paquetes desactualizados (`already built` skip), firma con `xbps-rindex` y publica aquí. Se dispara manualmente, por push y cada hora.

## Firma
Paquetes e índices firmados con RSA (`xbps-rindex --sign`). La llave privada vive en `secrets.XBPS_PRIVATE_KEY` — nunca en git.

