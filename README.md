# Omashiri ISO

The installer image for Omashiri, a small headless Linux server distribution. It is a fork of [omacom/omarchy-iso](https://github.com/omacom/omarchy-iso), kept as a fork so upstream kernel, boot and pipeline fixes can still be pulled. This repo builds x86_64 images only.

The ISO boots to a console installer, writes a pre-built Arch Linux root image (a zstd-compressed btrfs partition image) onto the target with `zstdcat | dd`, installs the per-machine packages from the bundled mirror, runs target setup in a chroot, creates the user, and provisions it. The installed system comes up headless and is reached over SSH.

Status: work in progress. The package list, ISO wiring and validation are tracked in [omashiri/omashiri](https://github.com/omashiri/omashiri/issues). The product definition is `plans/omashiri.md` in that repo.

## Related repositories

| Repository | Role |
| --- | --- |
| [omashiri/omashiri](https://github.com/omashiri/omashiri) | Installer payload, server package manifest (`install/omarchy-server.packages`), server defaults. Default branch `quattro`. |
| omashiri/omashiri-iso (this repo) | ISO composition and build. |
| [omashiri/omashiri-pkgs](https://github.com/omashiri/omashiri-pkgs) | Package repository for Omashiri's own packages. |

Identifiers, package names and `OMARCHY_*` variables keep their upstream names for now, so upstream changes stay easy to pull.

## Build the ISO

Requires Docker (or a compatible container runtime) on a Linux host with KVM.

```bash
./bin/omarchy-iso-make
```

Output goes into `./release`. By default the build tracks the `quattro` installer branch and the stable package channel. Useful options:

- `--edge`, `--rc`, `--dev`: build against another package channel.
- `--local-source <installer-checkout> <pkgs-checkout>`: build from local checkouts, for example `../omashiri` and `../omashiri-pkgs`. The first argument is the installer payload repo (runtime commands, configs, setup scripts, migrations). The installer UI itself lives in this repo.
- `--no-cache`, `--keep-pkg-cache`: control the package caches.

## Boot and test

```bash
./bin/omarchy-iso-boot [release/omarchy.iso]    # boot the ISO in QEMU
./test/all                                      # fast unit tests, no VM or ISO needed
./bin/omarchy-iso-test [release/omarchy.iso]    # drive a full install in a headless VM
./test/integration release/omarchy.iso          # integration scenarios in test/integration.d/
./test/upgrade-test                             # upgrade testing
```

The acceptance harness (`omarchy-iso-test`) drives the real installer through QMP screendumps and OCR. It is inherited from upstream and still assumes a desktop session in places; adapting it to the headless install is tracked in the validation issue.

Pass `--encrypt` to `omarchy-iso-test` to drive the encrypted install flow. LUKS is optional on Omashiri: the default install is plain btrfs.

## Autoinstall

The ISO installs itself with no keyboard when it finds its configuration on a second drive. Attach a drive labeled `cidata` alongside the ISO and the installer copies the config off it and skips the configurator. With no such drive, the wizard runs as usual. `cidata` is the cloud-init `NoCloud` label, so Proxmox, libvirt and Packer already know how to attach one.

## Translations

The installer's catalogs live in `configs/airootfs/usr/share/omarchy-iso/i18n/`. Add a string to `en.json` and print it with `t <key> [args]`. `test/unit/test_installer_i18n.py` checks keys, placeholders and font coverage.

## Release, signing and upload

`bin/omarchy-iso-release`, `omarchy-iso-sign` and `omarchy-iso-upload` are inherited from upstream and still target Omarchy's signing key and storage. They are not usable for Omashiri releases until Omashiri has its own.

## License

MIT. See `LICENSE`.
