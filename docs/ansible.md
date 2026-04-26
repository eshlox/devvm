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

Node is conditional. It is installed through `fnm` only when `NODE_VERSION` is set or
when configured AI npm packages require it. DevVM writes only the minimal PATH/API
environment blocks needed for those configured tools.

The `llama_cpp` role only runs for the dedicated AI VM (`DEVVM_ROLE="ai"`). Development
VMs skip llama.cpp model installation and instead receive helpers that call the AI VM
endpoint.
