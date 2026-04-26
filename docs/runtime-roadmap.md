# Runtime Roadmap

## Language

The current shell implementation should stay for now. DevVM mostly validates config,
renders Lima options, and calls Lima and Ansible. Rewriting that coordination layer in
Rust, Go, Zig, or Swift would produce a nicer single binary, but it would not remove the
important runtime dependencies: Lima and Ansible.

Rust or Go becomes worth it if the CLI grows a real config parser, locking, structured
logs, a stable library API, or a GUI backend. Until then, the safer path is to keep the
shell small and heavily tested.

## GUI

A macOS GUI can be useful later, but it should wrap the same CLI/config model rather
than replace it. A practical GUI would need VM list/start/stop/delete, config editing,
logs, key display, AI VM status, and safe share management.

The smallest useful version is a SwiftUI menu-bar app that shells out to `devvm`. A full
management app is a separate product-sized effort.

## Apple Container

Apple's `container` runtime is worth watching, but it is not a drop-in replacement for
DevVM today. It currently targets macOS 26 on Apple silicon, is pre-1.0, and is
optimized for OCI containers rather than long-lived mutable development VMs.

DevVM should keep the VM lifecycle behind `lib/lima.sh` so a future backend can be
introduced without changing Ansible roles, chezmoi usage, or the user config format.
