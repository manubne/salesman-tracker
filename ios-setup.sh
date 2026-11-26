#!/bin/bash
# Puts the BNEOne iPhone project on this Mac for testing on your own iPhone (free Apple ID).
# Safe to run again: it fetches the latest app code and rebuilds the project folder.
set -e
DIR="$HOME/bneone-ios"
mkdir -p "$DIR" && cd "$DIR"
echo "1/5 Downloading the latest app code…"
curl -fsSL -o appcode.b64 https://raw.githubusercontent.com/manubne/salesman-tracker/main/appcode.b64
base64 -D -i appcode.b64 -o app.zip
rm -rf app && unzip -q app.zip && cd app
echo "2/5 Creating the iPhone project…"
# a separate test identifier, so the real App Store identifier stays free for the company account
flutter create --org org.bne.test --platforms=ios . > /dev/null
echo "3/5 Setting name, permissions and minimum iOS…"
P=ios/Runner/Info.plist
pl() { /usr/libexec/PlistBuddy -c "$1" "$P"; }
pl "Set :CFBundleDisplayName BNEOne Test" 2>/dev/null || pl "Add :CFBundleDisplayName string 'BNEOne Test'"
add() { pl "Delete :$1" 2>/dev/null || true; pl "Add :$1 string '$2'"; }
add NSLocationWhenInUseUsageDescription "BNEOne uses your location to verify customer visits and check-ins."
add NSLocationAlwaysAndWhenInUseUsageDescription "While you are on duty, BNEOne records your route so visits and travel claims are verified. Tracking stops when you end your day."
add NSCameraUsageDescription "BNEOne uses the camera for site photos, bills, visiting cards and machine serial numbers."
add NSPhotoLibraryUsageDescription "BNEOne lets you attach photos and bills from your gallery."
add NSMicrophoneUsageDescription "BNEOne does not record audio; the camera screen asks for this permission."
pl "Delete :UIBackgroundModes" 2>/dev/null || true
pl "Add :UIBackgroundModes array"
pl "Add :UIBackgroundModes:0 string location"
pl "Add :UIBackgroundModes:1 string fetch"
sed -i '' "s/^# platform :ios.*/platform :ios, '15.5'/" ios/Podfile
sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*;/IPHONEOS_DEPLOYMENT_TARGET = 15.5;/g' ios/Runner.xcodeproj/project.pbxproj
echo "4/5 Getting packages (a few minutes the first time)…"
flutter pub get > /dev/null
(cd ios && pod install > /dev/null)
echo "5/5 Opening the project in Xcode…"
open ios/Runner.xcworkspace
echo
echo "Done. The project is in $DIR/app"
