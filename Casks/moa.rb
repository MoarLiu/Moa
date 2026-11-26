cask "moa" do
  arch arm: "arm64", intel: "x86_64"

  version "1.10.0"
  sha256 arm:   "ab2accdcbb58da01a0c3a98e2f75b1df55e36d8880a1ccf6c78334c9e2283a6b",
         intel: "d2cfd1c6c31933dbff5b61d48dc2d5c103bb21617612df9a2bbbca7f32dc0fd2"

  url "https://github.com/MoarLiu/Moa/releases/download/v#{version}/Moa-#{version}-macos-#{arch}.dmg"
  name "Moa"
  desc "Local macOS menu bar control plane for multi-AI-agent accounts, providers, and usage"
  homepage "https://github.com/MoarLiu/Moa"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :monterey"

  app "Moa.app"
  binary "#{appdir}/Moa.app/Contents/MacOS/Moa", target: "moa"

  zap trash: [
    "~/Library/Application Support/Moa",
    "~/Library/Preferences/com.moarliu.moa.plist",
  ]
end
