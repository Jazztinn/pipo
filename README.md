<p align="center">
  <img src="app/Resources/PipoIcon.png" width="160" alt="Pipo logo">
</p>

# Pipo

Pipo is an unofficial macOS menu-bar companion for LPU Cavite students. It
keeps deadlines, course updates, messages, notifications, and published grades
close without writing to the LMS.

Pipo connects only to `https://lms.lpucavite.edu.ph` and stores LMS access in
the macOS Keychain. The project is in local beta development and is not
affiliated with or endorsed by Lyceum of the Philippines University.

## Install

Download the latest Pipo DMG from GitHub Releases, open it, and drag Pipo into
Applications. Launching Pipo opens onboarding or account settings; the menu-bar
icon opens the student dashboard. Pipo checks for signed updates every day and
asks before installing them.

## Principles

- Less input, more interaction.
- Convenience without burden.
- Read-only LMS access.
- Honest capability and offline states.

## Development

Requirements:

- macOS 14 or later
- Swift 6.3 or later
- Rust 1.88 or later
- Full Xcode for app archives and signing

```sh
swift test
cargo test --workspace --manifest-path rust/Cargo.toml
```

Run the local menu-bar beta:

```sh
cargo build --manifest-path rust/Cargo.toml --bin pipo-core
PIPO_CORE_PATH="$PWD/rust/target/debug/pipo-core" swift run PipoApp
```

Live LMS verification requires credentials entered locally. Never place LMS
tokens or passwords in the repository, fixtures, logs, or issue reports.

## Status

Pipo v0.1 targets a read-only local beta. Developer ID signing, notarization,
and Sparkle release publishing follow beta acceptance.

## License

MIT. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
