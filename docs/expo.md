# Expo

DevVM keeps source code inside the VM by default, which is not the most convenient setup
for iOS Simulator-heavy Expo work. The supported path is still VM-first:

```bash
devvm new myapp \
  --ports "3000 5173 8081 8084 19000 19001 19002" \
  --packages "nodejs nodejs-npm pnpm"
devvm create myapp
devvm enter myapp
git clone git@github.com:you/myapp.git ~/code/myapp
cd ~/code/myapp
pnpm install
pnpm expo start --host lan
```

For fnm, Claude, Codex, or other tools outside Fedora DNF, use a per-VM setup script:

```bash
devvm new myapp --setup "$HOME/.config/devvm/setup/myapp.sh"
```

Use explicit shares only for narrow file exchange. Do not mount a host project folder as
the normal workflow.
