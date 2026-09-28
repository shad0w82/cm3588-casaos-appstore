# cm3588-casaos-appstore

A personal **CasaOS App Store** (custom source) for RK3588 / CM3588 apps.
Add it once in CasaOS and every app under `Apps/` becomes one-click installable.

## Structure

```
Apps/
└── rkmon/
    └── docker-compose.yml   # RK3588 hardware monitor (isac322/rkmon) via gotty
                             # image: shad0w82/rkmon:0.3.1
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
| **rkmon** | `shad0w82/rkmon:0.3.1` | arm64 only; `privileged` + host `/proc`,`/sys`,`/dev` (NPU/RGA debugfs). Web terminal on port **7682**, auth fields editable at install. |

## Requirements

- Apps here target **arm64 / RK3588** (`x-casaos.architectures: [arm64]`).
- Each app's image must be published to a **public registry** (CasaOS pulls it;
  it can't build locally). Build/push instructions live with each app's source
  (e.g. rkmon is built from the `rkmon-casaos/` folder in the parent project).

## Adding a new app (checklist)

1. Build & push the app image to a public registry.
2. Create `Apps/<app>/docker-compose.yml` referencing that public image, with an
   `x-casaos` block (id, main, title, icon, category, port_map, env/volume/port
   descriptions).
3. Commit & push. In CasaOS, refresh the App Store (or re-add the source).
