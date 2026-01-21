#!/bin/bash

# Script to add Super Spaces files to SuperDimmer Xcode project
# This manually edits project.pbxproj to add the new files

PROJECT_FILE="SuperDimmer.xcodeproj/project.pbxproj"

echo "🚀 Adding Super Spaces files to Xcode project..."

# Generate unique IDs for the new files
SPACE_DETECTOR_REF=$(uuidgen | tr -d '-' | cut -c1-24)
SPACE_MONITOR_REF=$(uuidgen | tr -d '-' | cut -c1-24)
SUPER_SPACES_HUD_REF=$(uuidgen | tr -d '-' | cut -c1-24)
SUPER_SPACES_VIEW_REF=$(uuidgen | tr -d '-' | cut -c1-24)

SPACE_DETECTOR_BUILD=$(uuidgen | tr -d '-' | cut -c1-24)
SPACE_MONITOR_BUILD=$(uuidgen | tr -d '-' | cut -c1-24)
SUPER_SPACES_HUD_BUILD=$(uuidgen | tr -d '-' | cut -c1-24)
SUPER_SPACES_VIEW_BUILD=$(uuidgen | tr -d '-' | cut -c1-24)

SUPER_SPACES_GROUP=$(uuidgen | tr -d '-' | cut -c1-24)

echo "✓ Generated UUIDs"
echo "  SpaceDetector: $SPACE_DETECTOR_REF"
echo "  SpaceChangeMonitor: $SPACE_MONITOR_REF"
echo "  SuperSpacesHUD: $SUPER_SPACES_HUD_REF"
echo "  SuperSpacesHUDView: $SUPER_SPACES_VIEW_REF"
echo "  SuperSpaces Group: $SUPER_SPACES_GROUP"

# Backup project file
cp "$PROJECT_FILE" "$PROJECT_FILE.backup"
echo "✓ Backed up project file"

# Add PBXBuildFile entries (after UpdateChecker line)
perl -i -pe "s|(UC1234567890ABCDEF123456 /\* UpdateChecker.swift in Sources \*/.*)|$&\n\t\t${SPACE_DETECTOR_BUILD} /* SpaceDetector.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${SPACE_DETECTOR_REF} /* SpaceDetector.swift */; };\n\t\t${SPACE_MONITOR_BUILD} /* SpaceChangeMonitor.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${SPACE_MONITOR_REF} /* SpaceChangeMonitor.swift */; };\n\t\t${SUPER_SPACES_HUD_BUILD} /* SuperSpacesHUD.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${SUPER_SPACES_HUD_REF} /* SuperSpacesHUD.swift */; };\n\t\t${SUPER_SPACES_VIEW_BUILD} /* SuperSpacesHUDView.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${SUPER_SPACES_VIEW_REF} /* SuperSpacesHUDView.swift */; };|" "$PROJECT_FILE"

echo "✓ Added PBXBuildFile entries"

# Add PBXFileReference entries (after UpdateChecker line)
perl -i -pe "s|(UC9876543210FEDCBA987654 /\* UpdateChecker.swift \*/.*)|$&\n\t\t${SPACE_DETECTOR_REF} /* SpaceDetector.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SpaceDetector.swift; sourceTree = \"<group>\"; };\n\t\t${SPACE_MONITOR_REF} /* SpaceChangeMonitor.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SpaceChangeMonitor.swift; sourceTree = \"<group>\"; };\n\t\t${SUPER_SPACES_HUD_REF} /* SuperSpacesHUD.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SuperSpacesHUD.swift; sourceTree = \"<group>\"; };\n\t\t${SUPER_SPACES_VIEW_REF} /* SuperSpacesHUDView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SuperSpacesHUDView.swift; sourceTree = \"<group>\"; };|" "$PROJECT_FILE"

echo "✓ Added PBXFileReference entries"

# Add PBXGroup for SuperSpaces folder (after Settings group)
perl -i -pe "s|(17EAFFC9A6765DF8C3168EF8 /\* Settings \*/.*)(\n\t\t\);)|$1$2\n\t\t${SUPER_SPACES_GROUP} /* SuperSpaces */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t${SPACE_DETECTOR_REF} /* SpaceDetector.swift */,\n\t\t\t\t${SPACE_MONITOR_REF} /* SpaceChangeMonitor.swift */,\n\t\t\t\t${SUPER_SPACES_HUD_REF} /* SuperSpacesHUD.swift */,\n\t\t\t\t${SUPER_SPACES_VIEW_REF} /* SuperSpacesHUDView.swift */,\n\t\t\t);\n\t\t\tpath = SuperSpaces;\n\t\t\tsourceTree = \"<group>\";\n\t\t};|" "$PROJECT_FILE"

echo "✓ Added SuperSpaces PBXGroup"

# Add SuperSpaces group reference to main SuperDimmer group (after Settings)
perl -i -pe "s|(17EAFFC9A6765DF8C3168EF8 /\* Settings \*/,)|$&\n\t\t\t\t${SUPER_SPACES_GROUP} /* SuperSpaces */,|" "$PROJECT_FILE"

echo "✓ Added SuperSpaces to main group"

# Add to PBXSourcesBuildPhase (after SettingsManager.swift)
perl -i -pe "s|(9DF14CF8F541D544FC005E3B /\* SettingsManager.swift in Sources \*/,)|$&\n\t\t\t\t${SPACE_DETECTOR_BUILD} /* SpaceDetector.swift in Sources */,\n\t\t\t\t${SPACE_MONITOR_BUILD} /* SpaceChangeMonitor.swift in Sources */,\n\t\t\t\t${SUPER_SPACES_HUD_BUILD} /* SuperSpacesHUD.swift in Sources */,\n\t\t\t\t${SUPER_SPACES_VIEW_BUILD} /* SuperSpacesHUDView.swift in Sources */,|" "$PROJECT_FILE"

echo "✓ Added to PBXSourcesBuildPhase"

echo ""
echo "✅ Super Spaces files added to Xcode project!"
echo ""
echo "Next steps:"
echo "1. Open SuperDimmer.xcodeproj in Xcode"
echo "2. Verify SuperSpaces folder appears in Project Navigator"
echo "3. Build project (Cmd+B) to verify"
echo ""
echo "If something went wrong, restore backup:"
echo "  cp $PROJECT_FILE.backup $PROJECT_FILE"
