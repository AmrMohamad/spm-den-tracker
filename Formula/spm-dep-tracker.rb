class SpmDepTracker < Formula
  # Maintainer-only formula. Stable public installs are published from the
  # dedicated tap repo `AmrMohamad/homebrew-spm-den-tracker`.
  desc "Audit Swift Package Manager lockfiles, pinning strategy, schema, and update drift"
  homepage "https://github.com/AmrMohamad/spm-den-tracker"
  head "https://github.com/AmrMohamad/spm-den-tracker.git", branch: "main"

  depends_on xcode: ["16.0", :build] if build.head?
  depends_on macos: :sonoma

  def install
    system "swift", "build",
      "--configuration", "release",
      "--product", "spm-dep-tracker",
      "--disable-sandbox"

    bin.install ".build/release/spm-dep-tracker"
  end

  test do
    assert_match "Inspect Xcode-managed Swift Package dependencies", shell_output("#{bin}/spm-dep-tracker --help")
  end
end
