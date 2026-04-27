# Release Process

Releases should be reproducible enough to inspect, signed, and easy for users to verify.

## Maintainer Setup

Protect the repository:

- require pull-request review for `main`
- protect `v*` tags
- require CI before merge
- limit who can create releases
- keep release signing keys on hardware-backed or otherwise well-protected storage

Publish the trusted release signing fingerprint in `README.md` or release notes, then
set it in user config:

```bash
DEVVM_RELEASE_SIGNER_FINGERPRINTS="0123456789ABCDEF0123456789ABCDEF01234567"
```

## Create A Release

Update `CHANGELOG.md`, then create a signed annotated tag:

```bash
git tag -s v0.1.0 -m v0.1.0
git push origin main v0.1.0
```

The release workflow:

- runs `bash scripts/check.sh`
- creates `devvm-v<version>.tar.gz`
- creates `SHA256SUMS`
- creates a GitHub release
- uploads the archive and checksums
- creates a GitHub artifact attestation for release assets

## Update Homebrew Tap

The stable user install path is the `eshlox/devvm` Homebrew tap. After the GitHub
release is published, update `eshlox/homebrew-devvm`:

```bash
brew tap eshlox/devvm
cd "$(brew --repository eshlox/devvm)"
```

Edit `Formula/devvm.rb`:

```ruby
url "https://github.com/eshlox/devenv/releases/download/v0.1.0/devvm-v0.1.0.tar.gz"
sha256 "<sha256 from SHA256SUMS>"
```

Test before pushing:

```bash
brew audit --strict --online devvm
brew install --build-from-source devvm
brew test devvm
git add Formula/devvm.rb
git commit -m "devvm 0.1.0"
git push
```

Users can install directly with `brew install eshlox/devvm/devvm`, or with two commands:

```bash
brew tap eshlox/devvm
brew install devvm
```

## Verify A Release

Users can verify the tag:

```bash
git fetch --tags
git verify-tag v0.1.0
```

Users can verify Homebrew and copied installs:

```bash
devvm verify-install
```

GitHub artifact attestations can be verified with GitHub CLI:

```bash
gh attestation verify devvm-v0.1.0.tar.gz -R eshlox/devenv
```

## Emergency Response

If a release is compromised:

- delete or revoke the release tag if appropriate
- publish a security notice
- rotate the release signing key if it may be exposed
- publish a fixed release
- update the Homebrew tap to the fixed release
- tell users to run `brew update && brew upgrade devvm`
- tell users to rotate VM SSH/GPG keys if VM secrets may be affected
