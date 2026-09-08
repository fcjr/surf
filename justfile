# SHA-1 of "Developer ID Application: Left Shift Logical, LLC (KNBPD99JQM)"; the hash is
# unambiguous when the certificate sits in more than one keychain (name matching is not).
sign_identity := env_var_or_default("SIGN_IDENTITY", "CB04D37CA86780520028A6E9D451C74A36B4FBBC")
notary_profile := env_var_or_default("NOTARY_PROFILE", "notary")

# CI overrides these from the release tag; local builds use project.yml defaults.
app_version := env_var_or_default("APP_VERSION", "")
app_build := env_var_or_default("APP_BUILD", "")
version_flags := (if app_version != "" { "MARKETING_VERSION=" + app_version } else { "" }) + " " + (if app_build != "" { "CURRENT_PROJECT_VERSION=" + app_build } else { "" })

scheme := "Surf"
build_dir := ".build"
app := build_dir + "/Build/Products/Debug/Surf.app"

# Show available recipes
default:
    @just --list

# Bump version (major|minor|patch), commit, and tag; push to release
bump level="patch":
    #!/usr/bin/env bash
    set -euo pipefail
    current=$(grep -E 'MARKETING_VERSION:' project.yml | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
    build=$(grep -E 'CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*"([0-9]+)".*/\1/')
    IFS=. read -r major minor patch <<< "$current"
    case "{{ level }}" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
        *) echo "usage: just bump [major|minor|patch]" >&2; exit 1 ;;
    esac
    next="$major.$minor.$patch"
    next_build=$((build + 1))
    sed -i '' -E "s/MARKETING_VERSION: \"$current\"/MARKETING_VERSION: \"$next\"/" project.yml
    sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"$build\"/CURRENT_PROJECT_VERSION: \"$next_build\"/" project.yml
    git add project.yml
    git commit -m "v$next"
    echo "Bumped $current -> $next (build $next_build)"
    echo "Release with: git push && just release"

# Release the version at HEAD: verify it's pushed and newer than the
# latest tag, then tag and push the tag (which triggers the CI release)
release:
    #!/usr/bin/env bash
    set -euo pipefail
    version=$(grep -E 'MARKETING_VERSION:' project.yml | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
    tag="v$version"
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "error: uncommitted changes - commit or stash first" >&2
        exit 1
    fi
    git fetch origin main --tags
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
        echo "error: HEAD is not the latest commit on origin/main - pull or push first" >&2
        exit 1
    fi
    latest=$(git ls-remote --tags origin 'v*' | sed -E 's|.*refs/tags/||' \
        | awk '!/\^{}$/' | sort -V | tail -1)
    if [ -n "$latest" ]; then
        newest=$(printf '%s\n%s\n' "$latest" "$tag" | sort -V | tail -1)
        if [ "$tag" = "$latest" ] || [ "$newest" != "$tag" ]; then
            echo "error: $tag is not newer than the latest released tag ($latest) - run 'just bump' first" >&2
            exit 1
        fi
    fi
    if git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
        if [ "$(git rev-parse "$tag^{commit}")" != "$(git rev-parse HEAD)" ]; then
            echo "error: local tag $tag already exists but points at a different commit" >&2
            exit 1
        fi
    else
        git tag "$tag"
    fi
    git push origin "$tag"
    echo "Released $tag - CI is building. Watch with: gh run watch"

# Generate the Xcode project
gen:
    xcodegen generate --quiet

# Build the app (Debug)
build: gen
    xcodebuild -project Surf.xcodeproj -scheme {{ scheme }} -configuration Debug \
        -derivedDataPath {{ build_dir }} -quiet build

# Build and launch the app; any running copy is quit first
run: build
    -pkill -x Surf
    open -n {{ app }}

stop:
    -pkill -x Surf

test: gen
    xcodebuild -project Surf.xcodeproj -scheme {{ scheme }} -derivedDataPath {{ build_dir }} -destination "platform=macOS" -quiet test

# Follow the app's os_log output
log:
    log stream --predicate 'subsystem == "com.leftshift.surf"' --style compact

# Generate and open in Xcode
open: gen
    xed Surf.xcodeproj

# Build Release, sign with Developer ID, and package a DMG
pkg: gen
    rm -rf {{ build_dir }}/pkg
    xcodebuild -project Surf.xcodeproj -scheme {{ scheme }} -configuration Release \
        -derivedDataPath {{ build_dir }} -quiet build {{ version_flags }} CODE_SIGN_IDENTITY="{{ sign_identity }}"
    mkdir -p {{ build_dir }}/pkg/dmg
    cp -R {{ build_dir }}/Build/Products/Release/Surf.app {{ build_dir }}/pkg/dmg/
    # Sparkle's nested executables ship with Sparkle's own signature, which
    # notarization rejects - re-sign them inside-out with our identity.
    codesign --force --options runtime --timestamp --sign "{{ sign_identity }}" \
        "{{ build_dir }}/pkg/dmg/Surf.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
        --sign "{{ sign_identity }}" \
        "{{ build_dir }}/pkg/dmg/Surf.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
    codesign --force --options runtime --timestamp --sign "{{ sign_identity }}" \
        "{{ build_dir }}/pkg/dmg/Surf.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
    codesign --force --options runtime --timestamp --sign "{{ sign_identity }}" \
        "{{ build_dir }}/pkg/dmg/Surf.app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
    codesign --force --options runtime --timestamp --sign "{{ sign_identity }}" \
        "{{ build_dir }}/pkg/dmg/Surf.app/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime --timestamp \
        --entitlements Surf/Resources/Surf.entitlements \
        --sign "{{ sign_identity }}" {{ build_dir }}/pkg/dmg/Surf.app
    codesign --verify --strict --deep {{ build_dir }}/pkg/dmg/Surf.app
    rm -f {{ build_dir }}/Surf.dmg
    create-dmg \
        --volname "Surf" \
        --window-pos 200 150 \
        --window-size 620 420 \
        --icon-size 128 \
        --icon "Surf.app" 160 205 \
        --hide-extension "Surf.app" \
        --app-drop-link 460 205 \
        --no-internet-enable \
        {{ build_dir }}/Surf.dmg {{ build_dir }}/pkg/dmg
    codesign --force --timestamp --sign "{{ sign_identity }}" {{ build_dir }}/Surf.dmg
    @echo "Signed DMG at {{ build_dir }}/Surf.dmg"

# Notarize and staple the DMG (once: xcrun notarytool store-credentials notary)
notarize: pkg
    xcrun notarytool submit {{ build_dir }}/Surf.dmg \
        --keychain-profile "{{ notary_profile }}" --wait
    xcrun stapler staple {{ build_dir }}/Surf.dmg

# Package a Sparkle update zip and generate the appcast. Enclosures point at
# GitHub release assets; normally CI runs this on tag push (see release.yml).
# The private key lives in the login keychain under account "Surf"
# (generate_keys --account Surf); CI uses SPARKLE_PRIVATE_KEY_FILE instead.
appcast: pkg
    #!/usr/bin/env bash
    set -euo pipefail
    version=$(plutil -extract CFBundleShortVersionString raw \
        {{ build_dir }}/pkg/dmg/Surf.app/Contents/Info.plist)
    mkdir -p {{ build_dir }}/updates
    ditto -c -k --keepParent {{ build_dir }}/pkg/dmg/Surf.app \
        "{{ build_dir }}/updates/Surf-$version.zip"
    sparkle_bin={{ build_dir }}/SourcePackages/artifacts/sparkle/Sparkle/bin
    "$sparkle_bin/generate_appcast" {{ build_dir }}/updates \
        ${SPARKLE_PRIVATE_KEY_FILE:+--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE"} \
        ${SPARKLE_PRIVATE_KEY_FILE:---account Surf} \
        --download-url-prefix "https://github.com/fcjr/surf/releases/download/v$version/"
    echo "Appcast at {{ build_dir }}/updates/appcast.xml"

# Remove generated project and build artifacts
clean:
    rm -rf {{ build_dir }} dist Surf.xcodeproj
