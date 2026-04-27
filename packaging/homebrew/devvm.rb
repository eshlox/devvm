class Devvm < Formula
  desc "Small Lima-based project VM manager"
  homepage "https://github.com/eshlox/devenv"
  url "https://github.com/eshlox/devenv/releases/download/v0.1.0/devvm-v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_SHA256"
  license "MIT"

  depends_on "lima"

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"bin/devvm"
  end

  test do
    system bin/"devvm", "--help"
  end
end
