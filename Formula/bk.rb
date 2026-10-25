# The Brigade's Homebrew formula: `brew install mhmzdev/brigade/bk`.
#
# This file is the template. The release workflow (.github/workflows/release.yml) fills in
# the sha256 of the tagged tarball and pushes the result to the tap, mhmzdev/homebrew-brigade,
# so the copy there is the one Homebrew reads. Edit this one; never the tap's by hand.
class Bk < Formula
  desc "Brigade kitchen: run several Claude Code sessions like a professional kitchen"
  homepage "https://github.com/mhmzdev/claude-code-brigade"
  url "https://github.com/mhmzdev/claude-code-brigade/archive/refs/tags/v0.27.1.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # filled in by the release workflow
  license "MIT"
  head "https://github.com/mhmzdev/claude-code-brigade.git", branch: "main"

  depends_on "node"
  depends_on "tmux"

  # homebrew-core's bk is an EPUB reader; both put a `bk` on the PATH.
  conflicts_with "bk", because: "both install a `bk` binary"

  def install
    # The plugin folder is the kitchen; bin/bk finds it as ../plugins/bk from its own real path.
    libexec.install "plugins", "bin"
    bin.install_symlink libexec/"bin/bk"
  end

  def caveats
    <<~EOS
      bk starts Claude Code sessions, so Claude Code must be installed and logged in:
        https://claude.com/claude-code
      Upgrade with the full name, brew upgrade mhmzdev/brigade/bk: a bare `bk` is
      Homebrew's own formula of that name, an EPUB reader.

      In a repo set up for the Brigade (/bk:setup inside claude):
        bk open     start the kitchen and sit with the sous
        bk stop     pause it; bk open resumes every session where it was
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/bk version")
    assert_match "bk open", shell_output("#{bin}/bk help")
  end
end
