# Runtime Roadmap

## Language

The current shell implementation should stay for now. DevVM mostly validates config,
renders Lima options, calls Lima, and runs a small shell provisioner. Rewriting that
coordination layer in Rust, Go, Zig, or Swift would produce a nicer single binary, but
it would not remove the important runtime dependency: Lima.

Rust or Go becomes worth it if the CLI grows a real config parser, locking, structured
logs, a stable library API, or a GUI backend. Until then, the safer path is to keep the
shell small and heavily tested.

## GUI

A macOS GUI can be useful later, but it should wrap the same CLI/config model rather
than replace it. A practical GUI would need VM list/start/stop/delete, config editing,
logs, key display, and safe share management.

The smallest useful version is a SwiftUI menu-bar app that shells out to `devvm`. A full
management app is a separate product-sized effort.

## Apple Container

Apple's `container` runtime is worth watching, but it is not a drop-in replacement for
DevVM. Its model is optimized for OCI containers rather than long-lived mutable
development VMs with project-local disks, VM-local SSH keys, GPG subkeys, and backups.

DevVM should keep the VM lifecycle behind `lib/lima.sh` so a future backend can be
introduced without changing the user config format.
