#!/bin/bash
# Puts the BNEOne iPhone project on this Mac for testing on your own iPhone (free Apple ID).
# Safe to run again: it fetches the latest app code and rebuilds the project folder.
set -e
DIR="$HOME/bneone-ios"
MODE="${1:-phone}"   # "sim" = build for the Mac's iPhone simulator and start it there
FREE=$(df -g "$HOME" | awk 'NR==2{print $4}')
echo "Free disk space: ${FREE} GB"
if [ "${FREE:-0}" -lt 10 ]; then
  echo "STOP: this Mac has less than 10 GB free. Building the iPhone app needs about 10 GB."
  echo "Free up space (empty the Bin, delete large downloads), then run this again."
  exit 1
fi
mkdir -p "$DIR" && cd "$DIR"
echo "1/5 Downloading the latest app code…"
curl -fsSL -o appcode.b64 https://raw.githubusercontent.com/manubne/salesman-tracker/main/appcode.b64
base64 -D -i appcode.b64 -o app.zip
rm -rf app && unzip -q app.zip && cd app
if [ "$MODE" = "sim" ]; then
  # the visiting-card reader (Google ML Kit) cannot be built for the simulator on Apple-silicon Macs: leave it out of this test build only
  sed -i '' '/google_mlkit_text_recognition/d' pubspec.yaml
  cat > lib/services/card_scanner.dart <<'DART'
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'card_parser.dart';

/// Simulator test build: the photo can be picked, but the card is not read (the reader only runs on a real phone).
class CardScanner {
  static final _picker = ImagePicker();
  static Future<(Uint8List, String)?> capture({bool fromGallery = false}) async {
    final x = await _picker.pickImage(source: fromGallery ? ImageSource.gallery : ImageSource.camera, maxWidth: 2000, maxHeight: 2000, imageQuality: 88);
    if (x == null) return null;
    return (await x.readAsBytes(), x.path);
  }

  static Future<CardData?> read(String path) async => null;
}
DART
fi
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
# Google Maps key for the iPhone app (limited in Google Cloud to Maps SDK for iOS and this app's bundle IDs)
perl -0pi -e 's/import Flutter\n/import Flutter\nimport GoogleMaps\n/; s/(\s*)(GeneratedPluginRegistrant\.register)/$1GMSServices.provideAPIKey("AIzaSyBl7Bd642INeLQaR8olZGMy2ZP0fKC5W5U")$1$2/' ios/Runner/AppDelegate.swift
echo "4/5 Getting packages (a few minutes the first time)…"
flutter pub get > /dev/null
(cd ios && pod install > /dev/null)
if [ "$MODE" = "sim" ]; then
  echo "5/5 Building for the simulator (several minutes)…"
  flutter build ios --simulator
  BOOTED=$(xcrun simctl list devices booted | grep -c Booted || true)
  if [ "$BOOTED" = "0" ]; then
    UDID=$(xcrun simctl list devices available | grep -E "iPhone" | head -1 | grep -oE "[0-9A-F-]{36}")
    echo "Starting a simulated iPhone ($UDID)…"
    xcrun simctl boot "$UDID"
  fi
  xcrun simctl install booted build/ios/iphonesimulator/Runner.app
  xcrun simctl launch booted org.bne.test.salesmanTracker
  open -a Simulator 2>/dev/null || open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app 2>/dev/null || echo "To see the phone screen: Xcode menu > Open Developer Tool > Device Hub"
  echo
  echo "Done. BNEOne Test is running on the simulated iPhone."
  exit 0
fi
echo "5/5 Opening the project in Xcode…"
open ios/Runner.xcworkspace
echo
echo "Done. The project is in $DIR/app"
