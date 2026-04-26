# Explicit Shares

DevVM does not mount macOS project folders. Repositories should be cloned inside the VM
under `/code`.

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

DevVM rejects broad host paths such as `$HOME` and protected guest paths such as
`/code`, `/home`, and `/etc`. A share still weakens isolation for that mounted path; use
it only for deliberate file transfer.
