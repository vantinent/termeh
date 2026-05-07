# Termeh SSH Client

A simple SSH management client for Linux Ubuntu built with Flutter.

## Features

- **Secure Storage**: Credentials are encrypted and stored using `flutter_secure_storage`.
- **Connection Management**: Add, edit, and delete SSH connection profiles.
- **One-Click Connect**: Quickly open a terminal session to your saved servers.
- **Full Terminal Emulation**: Integrated terminal with scrollback support.
- **Linux Native**: Optimized for Ubuntu and other Linux distributions.

## Prerequisites

To build and run this application on Ubuntu, you need:

1. **Flutter SDK**: [Install Flutter](https://docs.flutter.dev/get-started/install/linux)
2. **System Dependencies**:
   ```bash
   sudo apt-get update
   sudo apt-get install -y libsecret-1-dev
   ```

## Getting Started

1. Initialize the Flutter project (if not already done):
   ```bash
   flutter create --platforms=linux .
   ```
2. Get dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run -d linux
   ```

## Security Note

Credentials are stored using `flutter_secure_storage`, which on Linux utilizes `libsecret` to store secrets in the system's secret service (e.g., GNOME Keyring).

## macOS Release DMG

To build a shareable macOS `.dmg`, run:

```bash
./scripts/package_macos_dmg.sh
```

The script builds the macOS release app, stages `Termeh.app` beside an `Applications` link, and writes the final DMG to `dist/Termeh-macos.dmg`.

On macOS, use `Cmd-N` or the `Window > New Window` menu item to open another app window.

## Linux Packages

To build a Debian package for Linux, run:

```bash
fastforge package --platform=linux --targets=deb
```

This creates a Linux `.deb` package for distribution on Debian-based systems.

To build a Snap package, run:

```bash
snapcraft pack
```

This produces a `.snap` package in the `dist` directory for local testing or
distribution.
