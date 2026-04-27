# Ansible

DevVM generates inventory at:

```text
~/.local/share/devvm-state/generated/inventory.ini
```

Run provisioning manually with:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  -i ~/.local/share/devvm-state/generated/inventory.ini \
  ansible/site.yml
```

The CLI regenerates inventory before every `create`, `update`, and `update-all` run.

Fedora package management uses `ansible.builtin.dnf5`. Base packages are kept minimal:
Git, SSH/GPG support, Python, archive utilities, `jq`, `curl`, and runtime helpers
required by DevVM itself.

OS package upgrades are opt-in:

```bash
DEVVM_UPGRADE_PACKAGES="1"
```

Provisioned tools come from Fedora DNF packages. The `chezmoi` role installs the Fedora
`chezmoi` package. The Node role installs Fedora `nodejs`, `nodejs-npm`, and `pnpm`
packages only when `INSTALL_NODE=1`. Existing configs that still set `NODE_VERSION`
continue to opt in for compatibility, but Fedora's enabled repositories select the
actual Node version.

The `llama_cpp` role only runs for the dedicated AI VM (`DEVVM_ROLE="ai"`). Development
VMs skip llama.cpp model installation and instead receive helpers that call the AI VM
endpoint.
