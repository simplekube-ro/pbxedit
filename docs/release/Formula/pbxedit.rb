# Task 5.1 of release-distribution: Formula/pbxedit.rb in the tap
# (tap: simplekube-ro/homebrew-tap). Fill the <...> values on the
# first release; the release workflow rewrites `url` and `sha256` from then
# on. The version is derived from the url (an explicit `version` line is a
# `brew audit` warning). `license` waits on task 1.2.

class Pbxedit < Formula
  desc "Manage file membership in an Xcode project.pbxproj"
  homepage "https://github.com/simplekube-ro/pbxedit"
  url "https://github.com/simplekube-ro/pbxedit/releases/download/v0.1.0/pbxedit-0.1.0-macos-universal.tar.gz"
  sha256 "<sha256 of the archive, from the release's .sha256 file>"
  license "MIT"

  depends_on :macos
  depends_on macos: :ventura

  def install
    bin.install "pbxedit"
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/pbxedit --version").strip
  end
end
