# cm3588-casaos-appstore

A personal **CasaOS App Store** (custom source) for RK3588 / CM3588 apps.
Add it once in CasaOS and every app under `Apps/` becomes one-click installable.

## Structure

```
Apps/
├── rkmon/
│   ├── docker-compose.yml   # RK3588 hardware monitor (isac322/rkmon) via gotty
│   │                        # image: shad0w82/rkmon:0.4.0
│   └── docker/              # how that image is built and published (not read by CasaOS)
│       ├── Dockerfile
│       ├── entrypoint.sh
│       ├── build.sh
│       └── README.md
└── rktopng/
    ├── docker-compose.yml   # RkTopNG: web dashboard + Prometheus exporter for the RK3588
    │                        # image: shad0w82/rktopng:0.1.0
    ├── icon.png
    └── docker/              # how that image is built and published (not read by CasaOS)
        ├── Dockerfile
        ├── build.sh
        └── README.md
```

Add more apps later by creating `Apps/<app>/docker-compose.yml` (with an
`x-casaos` block) and pushing — CasaOS picks them up from the same source.

## Add this store in CasaOS

1. CasaOS → **App Store** → settings menu (⋮/gear) → **Add source**.
2. Paste the repo's archive URL:
   ```
   https://github.com/<github-user>/cm3588-casaos-appstore/archive/refs/heads/main.zip
   ```
   (GitHub serves the repo as a zip; CasaOS extracts it and reads `Apps/`.)
3. The store's apps now appear in the App Store → one-click **Install**.

## Apps

| App | Image | Notes |
|-----|-------|-------|
| **rkmon** | `shad0w82/rkmon:0.4.0` | arm64 only; `privileged` + host `/proc`,`/sys`,`/dev` (NPU/RGA debugfs). Web terminal on port **7682**, auth fields editable at install. |
| **rktopng** | `shad0w82/rktopng:0.1.0` | arm64 only; `privileged` + host `/proc`,`/sys`,`/` mounted read-only. Dashboard and Prometheus `/metrics` on port **9888**. Optional login (user + password, both or neither; it protects `/metrics` too) and sub-path for a reverse proxy, both empty by default and editable at install. Source: [shad0w82/rktopng](https://github.com/shad0w82/rktopng). |

## Requirements

- Apps here target **arm64 / RK3588** (`x-casaos.architectures: [arm64]`).
- Each app's image must be published to a **public registry** (CasaOS pulls it;
  it can't build locally). Each app keeps what builds its image in a `docker/` folder next to its compose,
  with a `build.sh` that makes the image from a release and refuses to overwrite a published version:
  [`Apps/rkmon/docker/`](Apps/rkmon/docker/README.md) (from the rkmon release) and
  [`Apps/rktopng/docker/`](Apps/rktopng/docker/README.md) (from a RkTopNG release).

## Adding a new app (checklist)

1. Build & push the app image to a public registry.
2. Create `Apps/<app>/docker-compose.yml` referencing that public image, with an
   `x-casaos` block (id, main, title, icon, category, port_map, env/volume/port
   descriptions).
3. Commit & push. In CasaOS, refresh the App Store (or re-add the source).
