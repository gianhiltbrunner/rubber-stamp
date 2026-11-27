class RubberStamp < Formula
  desc "Menu bar app that lists or auto-approves GitHub PRs you are asked to review"
  homepage "https://github.com/gianhiltbrunner/rubber-stamp"
  url "https://github.com/gianhiltbrunner/rubber-stamp/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "SHA256_PLACEHOLDER"
  license "MIT"
  head "https://github.com/gianhiltbrunner/rubber-stamp.git", branch: "main"

  depends_on macos: :ventura
  depends_on "gh"

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin_path = Utils.safe_popen_read("swift", "build", "--disable-sandbox", "-c", "release", "--show-bin-path").strip
    system "scripts/make-app.sh", "#{bin_path}/RubberStamp", prefix/"Rubber Stamp.app", version.to_s
    (bin/"rubber-stamp").write <<~SH
      #!/bin/sh
      exec open "#{opt_prefix}/Rubber Stamp.app"
    SH
  end

  def caveats
    <<~EOS
      Start it with:
        rubber-stamp
      It uses your GitHub CLI login; run `gh auth login` first if needed.
      To show it in Launchpad and Spotlight:
        ln -sf "#{opt_prefix}/Rubber Stamp.app" /Applications/
    EOS
  end

  test do
    assert_path_exists prefix/"Rubber Stamp.app/Contents/MacOS/RubberStamp"
    assert_match "rubber-stamp", (prefix/"Rubber Stamp.app/Contents/Info.plist").read
  end
end
