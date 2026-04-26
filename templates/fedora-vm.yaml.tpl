minimumLimaVersion: "2.0.0"

vmType: "vz"
arch: "{{ LIMA_ARCH }}"

# Runtime creation uses the Lima 2.x built-in "{{ LIMA_TEMPLATE }}" template,
# then applies these settings with limactl create --set. This file is an audit
# record of DevVM intent, not the file passed to limactl.

cpus: {{ CPUS }}
memory: "{{ MEMORY }}"
disk: "{{ DISK }}"

user:
  name: "{{ DEVVM_GUEST_USER }}"
  home: "{{ DEVVM_GUEST_HOME }}"

mountType: "virtiofs"

{{ MOUNTS_BLOCK }}

networks:
  - vzNAT: true

{{ PORT_FORWARDS_BLOCK }}

containerd:
  system: false
  user: false
