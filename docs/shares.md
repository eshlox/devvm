# Explicit Shares

DevVM does not mount macOS project folders. Repositories should be cloned inside the VM
under `~/code`.

If you need file exchange, configure narrow explicit shares:

```bash
GLOBAL_MOUNTS="$HOME/devvm-share:/share:rw"
```

or per VM:

```bash
MOUNTS="$HOME/devvm-share:/share:rw"
```

Mount specs use:

```text
host_path:guest_path[:ro|rw]
```

DevVM rejects broad host paths such as `$HOME` and protected guest paths such as the
configured code directory, `/home`, and `/etc`. A share still weakens isolation for that
mounted path; use it only for deliberate file transfer.

Host share paths are canonicalized, so symlinks and `..` segments cannot bypass the
checks. DevVM also rejects sensitive host paths by default, including `.ssh`, `.aws`,
`.gnupg`, `.config`, `.docker`, `.kube`, `Library`, `Documents`, `Desktop`, and
`Downloads`.

Override only when you explicitly accept that risk:

```bash
DEVVM_ALLOW_SENSITIVE_MOUNTS="1"
```
