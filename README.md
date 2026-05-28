# Manifest Self-Hosted

Public distribution surface for **`manifest-installer`** — the CLI that installs
the [Manifest](https://www.manifestcyber.com) platform into self-hosted and
air-gapped Kubernetes environments.

This repository carries **release binaries and download instructions only**. The
platform source is not published here.

## Download the installer

Binaries for every release are published under
[Releases](https://github.com/manifest-cyber/manifest-self-hosted/releases) and
are downloadable anonymously — no GitHub account or token required. Each binary
ships with a matching `.sha256` checksum file.

Replace `<version>` with the version you've been instructed to install (for
example `2.0.0`); the release tag is that version prefixed with `v`. Binaries are
published for `linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64`, and
`windows/amd64`.

### Linux

```bash
base=https://github.com/manifest-cyber/manifest-self-hosted/releases/download/v<version>
curl -fsSL -O "$base/manifest-installer-linux-amd64"
curl -fsSL -O "$base/manifest-installer-linux-amd64.sha256"
sha256sum -c manifest-installer-linux-amd64.sha256   # prints "OK" on a match
chmod +x manifest-installer-linux-amd64
sudo mv manifest-installer-linux-amd64 /usr/local/bin/manifest-installer
```

### Windows (PowerShell)

```powershell
$base = "https://github.com/manifest-cyber/manifest-self-hosted/releases/download/v<version>"
Invoke-WebRequest -Uri "$base/manifest-installer-windows-amd64.exe" `
  -OutFile "$env:USERPROFILE\manifest-installer.exe"
Invoke-WebRequest -Uri "$base/manifest-installer-windows-amd64.exe.sha256" `
  -OutFile "$env:USERPROFILE\manifest-installer.exe.sha256"
(Get-FileHash "$env:USERPROFILE\manifest-installer.exe" -Algorithm SHA256).Hash.ToLower()
(Get-Content "$env:USERPROFILE\manifest-installer.exe.sha256").Split()[0]
```

The binaries are not code-signed today — verify the checksum above to confirm
integrity. Distribution-signing (cosign/sigstore) is tracked as a separate
hardening item.

## Documentation

Full install guides — internet-connected and air-gapped — live in the Manifest
documentation at <https://docs.manifestcyber.com>.

## Support

Contact Manifest support at **support@manifestcyber.com**.
