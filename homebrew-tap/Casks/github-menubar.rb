cask "github-menubar" do
  version "0.0.0"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"  # Update this after creating first release

  url "https://github.com/dondenton/GitHubMenuBar/releases/download/v#{version}/GitHubMenuBar.zip"
  name "GitHub MenuBar"
  desc "macOS menu bar app for monitoring GitHub pull requests"
  homepage "https://github.com/dondenton/GitHubMenuBar"

  # Requires macOS 13.0 or later
  depends_on macos: ">= :ventura"

  app "GitHubMenuBar.app"

  # Remove quarantine attribute (since app is unsigned)
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/GitHubMenuBar.app"]
  end

  zap trash: [
    "~/Library/Preferences/com.github.menubar.plist",
  ]

  caveats <<~EOS
    GitHub MenuBar requires the GitHub CLI (gh) to be installed and authenticated.

    If you don't have it installed:
      brew install gh
      gh auth login

    On first launch, you may need to grant accessibility permissions in:
      System Settings > Privacy & Security > Accessibility
  EOS
end
