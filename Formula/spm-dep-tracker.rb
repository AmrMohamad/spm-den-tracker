class SpmDepTracker < Formula
  desc "Audit Swift Package Manager lockfiles, pinning strategy, schema, and update drift"
  homepage "https://github.com/<org>/spm-den-tracker"
  url "https://github.com/<org>/spm-den-tracker/releases/download/v0.1.0/spm-dep-tracker-macos.tar.gz"
  sha256 "<REPLACE_WITH_RELEASE_SHA256>"
  license "MIT"

  depends_on macos: :ventura

  def install
    bin.install "spm-dep-tracker"
  end

  test do
    assert_match "Inspect Xcode-managed Swift Package dependencies", shell_output("#{bin}/spm-dep-tracker --help")
  end
end
