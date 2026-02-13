#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$ROOT_DIR/MetroAIScheduler.xcodeproj"
SCHEME="MetroAIScheduler"
CONFIGURATION="Release"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
DIST_APP_PATH="$DIST_DIR/MetroAIScheduler.app"
DIST_DMG_PATH="$DIST_DIR/MetroAIScheduler.dmg"

PYTHON_TAR="$ROOT_DIR/cpython-3.12.12+20260127-aarch64-apple-darwin-install_only.tar"
VENV_SITE_PACKAGES="$ROOT_DIR/env/lib/python3.12/site-packages"
PY_STAGING_DIR="$ROOT_DIR/build/python-runtime"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Missing Xcode project: $PROJECT_PATH" >&2
  exit 1
fi
if [[ ! -f "$PYTHON_TAR" ]]; then
  echo "Missing CPython runtime tarball: $PYTHON_TAR" >&2
  exit 1
fi
if [[ ! -d "$VENV_SITE_PACKAGES" ]]; then
  echo "Missing venv site-packages directory: $VENV_SITE_PACKAGES" >&2
  exit 1
fi

echo "[0/6] Clearing local build caches"
rm -rf "$DERIVED_DATA_PATH" "$ROOT_DIR/.build" "$DIST_APP_PATH" "$PY_STAGING_DIR"
rm -f "$DIST_DMG_PATH"

echo "[1/6] Building MetroAIScheduler.app (Release)"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "generic/platform=macOS" \
  build >/tmp/metro_ai_scheduler_xcodebuild.log

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/MetroAIScheduler.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but app bundle was not found at: $APP_PATH" >&2
  echo "See /tmp/metro_ai_scheduler_xcodebuild.log" >&2
  exit 1
fi

echo "[2/6] Embedding standalone Python runtime"
rm -rf "$PY_STAGING_DIR"
mkdir -p "$PY_STAGING_DIR"
tar -xf "$PYTHON_TAR" -C "$PY_STAGING_DIR"

PY_HOME_DEST="$APP_PATH/Contents/Resources/python"
rm -rf "$PY_HOME_DEST"
cp -R "$PY_STAGING_DIR/python" "$PY_HOME_DEST"

echo "[3/6] Copying venv site-packages (including OR-Tools)"
PY_SITE_DEST="$PY_HOME_DEST/lib/python3.12/site-packages"
mkdir -p "$PY_SITE_DEST"
rsync -a --delete "$VENV_SITE_PACKAGES/" "$PY_SITE_DEST/"
chmod +x "$PY_HOME_DEST/bin/python3" "$PY_HOME_DEST/bin/python3.12"

echo "[4/6] Verifying embedded Python can import OR-Tools"
PYTHONHOME="$PY_HOME_DEST" PYTHONPATH="$PY_SITE_DEST" \
  "$PY_HOME_DEST/bin/python3" -c "import ortools; print('embedded ortools', ortools.__version__)"

echo "[5/6] Creating distributable app in dist/"
mkdir -p "$DIST_DIR"
rm -rf "$DIST_APP_PATH"
ditto "$APP_PATH" "$DIST_APP_PATH"

# Re-sign ad hoc because we modified app contents post-build.
codesign --force --deep --sign - "$DIST_APP_PATH" >/dev/null 2>&1 || true

echo "[6/6] Packaging .dmg for distribution"
hdiutil create \
  -volname "MetroAIScheduler" \
  -srcfolder "$DIST_APP_PATH" \
  -ov \
  -format UDZO \
  "$DIST_DMG_PATH" >/tmp/metro_ai_scheduler_hdiutil.log

echo
echo "Build complete: $DIST_APP_PATH"
echo "DMG package: $DIST_DMG_PATH"
echo "xcodebuild log: /tmp/metro_ai_scheduler_xcodebuild.log"
echo "hdiutil log: /tmp/metro_ai_scheduler_hdiutil.log"
