#!/bin/sh

set -e

cd $CI_PRIMARY_REPOSITORY_PATH

# Install Flutter
git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Install Flutter artifacts for iOS
flutter precache --ios

# Install Flutter dependencies
flutter pub get

# Install CocoaPods
HOMEBREW_NO_AUTO_UPDATE=1
brew install cocoapods

# Install CocoaPods dependencies for iOS
cd ios
pod deintegrate
pod install --repo-update
cd ..

# Build IPA for App Store
flutter build ipa --release --export-method=app-store
