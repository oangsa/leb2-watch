# Flatpak preview

The manifest packages the complete Linux release bundle as
`dev.oangsa.leb2watch`. It uses the Freedesktop 25.08 runtime and builds the
AppIndicator compatibility libraries required by the current Linux tray
plugin. The existing Linux tray icon is installed under the application ID so
the sandbox-aware tray path can resolve it.

Flatpak autostart uses the app's XDG configuration path rather than the
third-party adapter's unpackaged `$HOME/.config` assumption. The manifest
grants only `xdg-config/autostart:create`, and the generated entry launches
`/usr/bin/flatpak run dev.oangsa.leb2watch`.

Build the release input first with a real HTTPS backend origin:

```bash
flutter build linux --release \
  --dart-define=APP_ENV=production \
  --dart-define=BACKEND_BASE_URL=https://<YOUR_BACKEND_ORIGIN>
```

Then build and export the Flatpak:

```bash
flatpak-builder --force-clean \
  --repo=build/flatpak-repo \
  build/flatpak \
  packaging/flatpak/dev.oangsa.leb2watch.json

flatpak build-bundle \
  build/flatpak-repo \
  build/leb2-watch.flatpak \
  dev.oangsa.leb2watch
```

The current host built the manifest with Flatpak 1.18.0, the Freedesktop 25.08
SDK/runtime, and `flatpak-builder` 1.4.10. On 2026-08-01 a fresh current-source
Linux Release bundle was built with `APP_ENV=development` and
`BACKEND_BASE_URL=http://localhost:5015` from a disposable writable Flutter
3.44.8 SDK copy. A Flatpak rebuild, bundle export, and user-scoped installation
update then passed; metadata/permission inspection, an in-sandbox
file/linker/symlink smoke, and a bounded 20-second Wayland launch also passed.
A host-side Swagger preflight and the same request from the installed Flatpak
sandbox both returned HTTP 200. An unauthenticated `/Semester` request returned
HTTP 401 from both namespaces. The exact packaged launch command used by the
generated autostart entry stayed alive for 15 seconds before its expected
timeout. No authenticated app flow or real login/reboot launch was run. Because
production rejects HTTP, the localhost artifact is development-only; a
distributable package must be rebuilt with `APP_ENV=production` and a real
operator-owned HTTPS origin. This is a repository-local preview manifest, not
a Flathub submission or publication configuration.

The package keeps access narrow: network, display sockets, GPU, notifications,
Secret Service, the current KDE StatusNotifier watcher, and the autostart
directory are explicitly requested. X11/GNOME runtime validation remains
outside the current preview scope.
