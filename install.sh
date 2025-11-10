#!/bin/bash

# GitHubMenuBar Installer
# curl -fsSL https://raw.githubusercontent.com/happycollision/GitHubMenuBar/main/install.sh | bash

set -e  # Exit on error

# Configuration
REPO="happycollision/GitHubMenuBar"
APP_NAME="GitHubMenuBar"
DOWNLOAD_URL=""
VERSION="latest"

# Installation options
REMOVE_QUARANTINE=false
MOVE_TO_APPLICATIONS=false
LIST_VERSIONS=false
TEMP_DIR=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --remove-quarantine)
      REMOVE_QUARANTINE=true
      shift
      ;;
    --move-to-applications)
      MOVE_TO_APPLICATIONS=true
      shift
      ;;
    --yolo)
      REMOVE_QUARANTINE=true
      MOVE_TO_APPLICATIONS=true
      shift
      ;;
    --list-versions)
      LIST_VERSIONS=true
      shift
      ;;
    --version)
      # Normalize version: allow "latest" or version with/without "v" prefix
      if [ "$2" = "latest" ]; then
        VERSION="latest"
      else
        # Add 'v' prefix if not present
        if [[ ! "$2" =~ ^v ]]; then
          VERSION="v$2"
        else
          VERSION="$2"
        fi
      fi
      shift 2
      ;;
    --help)
      echo "GitHubMenuBar Installer"
      echo ""
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --version VERSION         Install specific version (default: latest)"
      echo "                            VERSION can look like: 'latest', '0.3.0', or 'v0.3.0'"
      echo "  --remove-quarantine       Remove quarantine attributes (allows app to launch without right-click)"
      echo "  --move-to-applications    Move app to /Applications folder"
      echo "  --yolo                    Full auto install (enables --remove-quarantine and --move-to-applications)"
      echo "  --list-versions           List available versions and release URLs (no installation)"
      echo "  --help                    Show this help message"
      echo ""
      echo "Examples:"
      echo "  # YOLO mode - full auto install"
      echo "  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash -s -- --yolo"
      echo ""
      echo "  # Full installation (explicit flags)"
      echo "  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash -s -- --remove-quarantine --move-to-applications"
      echo ""
      echo "  # Download and extract only (you handle the rest)"
      echo "  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash"
      echo ""
      echo "  # Install specific version with YOLO"
      echo "  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash -s -- --version v0.3.0 --yolo"
      echo ""
      echo "  # List all available versions"
      echo "  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash -s -- --list-versions"
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Unknown option $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Function to print colored messages
print_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
  echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
  echo -e "${RED}✗${NC} $1"
}

# Function to cleanup on exit
cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    print_info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT

# Print banner (skip if just listing versions)
if [ "$LIST_VERSIONS" = false ]; then
  echo ""
  echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║${NC}   GitHubMenuBar Installer              ${BLUE}║${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
  echo ""

  # Check macOS version
  print_info "Checking system requirements..."
  OS_VERSION=$(sw_vers -productVersion)
  OS_MAJOR=$(echo "$OS_VERSION" | cut -d. -f1)
  if [ "$OS_MAJOR" -lt 13 ]; then
    print_error "This app requires macOS 13.0 (Ventura) or later"
    print_error "Your version: macOS $OS_VERSION"
    exit 1
  fi
  print_success "macOS version: $OS_VERSION"

  # Check for GitHub CLI
  if ! command -v gh &> /dev/null; then
    print_warning "GitHub CLI (gh) is not installed"
    print_info "GitHubMenuBar requires the GitHub CLI to function"
    print_info "Install it with: brew install gh"
    print_info "Then authenticate with: gh auth login"
    echo ""
    read -p "Continue installation anyway? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      print_info "Installation cancelled"
      exit 0
    fi
  else
    print_success "GitHub CLI is installed"

    # Check if authenticated
    if gh auth status &> /dev/null; then
      print_success "GitHub CLI is authenticated"
    else
      print_warning "GitHub CLI is not authenticated"
      print_info "Run 'gh auth login' after installation"
    fi
  fi
fi

# Determine download URL and version
if [ "$LIST_VERSIONS" = false ]; then
  print_info "Fetching release information..."
fi

# Always fetch the actual latest version for comparison
LATEST_VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)

if [ "$VERSION" = "latest" ]; then
  DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/${APP_NAME}.zip"
  ACTUAL_VERSION="$LATEST_VERSION"
  RELEASE_URL="https://github.com/${REPO}/releases/latest"
  VERSION_DISPLAY="$ACTUAL_VERSION (latest)"
else
  # VERSION already has 'v' prefix from argument parsing
  DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${APP_NAME}.zip"
  RELEASE_URL="https://github.com/${REPO}/releases/tag/${VERSION}"
  ACTUAL_VERSION="$VERSION"
  if [ "$VERSION" = "$LATEST_VERSION" ]; then
    VERSION_DISPLAY="$VERSION (latest)"
  else
    VERSION_DISPLAY="$VERSION"
  fi
fi

# List versions mode: show available versions and release info, then exit
if [ "$LIST_VERSIONS" = true ]; then
  echo ""

  # If no specific version requested, show all versions
  if [ "$VERSION" = "latest" ]; then
    # Fetch all releases (sorted oldest to newest)
    print_info "Fetching all available releases..."
    ALL_RELEASES=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases" | grep '"tag_name"' | cut -d'"' -f4 | tail -r)

    if [ -z "$ALL_RELEASES" ]; then
      print_warning "Could not fetch releases list"
    else
      echo ""
      print_info "Available versions (oldest to newest):"
      echo ""

      while IFS= read -r version; do
        release_url="https://github.com/${REPO}/releases/tag/${version}"
        if [ "$version" = "$LATEST_VERSION" ]; then
          echo "  ${version} (latest) - ${release_url}"
        else
          echo "  ${version} - ${release_url}"
        fi
      done <<< "$ALL_RELEASES"
      echo ""
    fi

    print_info "Latest version:"
    echo "  Version: ${VERSION_DISPLAY}"
    echo "  Release page: ${RELEASE_URL}"
    echo "  Download URL: ${DOWNLOAD_URL}"
  else
    # Specific version requested - validate it exists
    print_info "Validating version ${ACTUAL_VERSION}..."
    ALL_RELEASES=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases" | grep '"tag_name"' | cut -d'"' -f4)

    if echo "$ALL_RELEASES" | grep -q "^${ACTUAL_VERSION}$"; then
      print_success "Version ${ACTUAL_VERSION} found!"
      echo ""
      print_info "Version details:"
      echo "  Version: ${VERSION_DISPLAY}"
      echo "  Release page: ${RELEASE_URL}"
      echo "  Download URL: ${DOWNLOAD_URL}"
    else
      print_error "Version ${ACTUAL_VERSION} not found!"
      echo ""
      print_warning "Available versions:"
      echo ""
      echo "$ALL_RELEASES" | tail -r | while IFS= read -r version; do
        release_url="https://github.com/${REPO}/releases/tag/${version}"
        if [ "$version" = "$LATEST_VERSION" ]; then
          echo "  ${version} (latest) - ${release_url}"
        else
          echo "  ${version} - ${release_url}"
        fi
      done
      echo ""
      exit 1
    fi
  fi

  echo ""
  print_info "To install this version:"
  echo "  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash -s -- --version ${ACTUAL_VERSION} --yolo"
  echo ""
  exit 0
fi

print_info "Installing version: $VERSION_DISPLAY"

# Download the ZIP file
DOWNLOAD_DIR="$HOME/Downloads"
ZIP_PATH="${DOWNLOAD_DIR}/${APP_NAME}.zip"

print_info "Downloading ${APP_NAME}.zip to ~/Downloads..."
if curl -fsSL -o "$ZIP_PATH" "$DOWNLOAD_URL"; then
  print_success "Downloaded successfully"
else
  print_error "Download failed"
  print_error "URL: $DOWNLOAD_URL"
  exit 1
fi

# Extract to temporary directory
TEMP_DIR=$(mktemp -d)
print_info "Extracting to temporary directory..."
if unzip -q "$ZIP_PATH" -d "$TEMP_DIR"; then
  print_success "Extracted successfully"
else
  print_error "Extraction failed"
  exit 1
fi

APP_PATH="${TEMP_DIR}/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  print_error "Expected ${APP_NAME}.app not found in ZIP"
  exit 1
fi

# Handle quarantine attributes (opt-in)
if [ "$REMOVE_QUARANTINE" = true ]; then
  print_info "Removing quarantine attributes..."
  if xattr -cr "$APP_PATH"; then
    print_success "Quarantine attributes removed - app can launch normally"
  else
    print_warning "Failed to remove quarantine attributes"
    print_info "You'll need to right-click and select 'Open' on first launch"
  fi
else
  print_info "Quarantine attributes not removed (use --remove-quarantine to enable)"
  print_info "On first launch, right-click the app and select 'Open' (unsigned app)"
fi

# Move to Applications (opt-in)
if [ "$MOVE_TO_APPLICATIONS" = true ]; then
  FINAL_APP_PATH="/Applications/${APP_NAME}.app"

  # Check if app already exists in Applications
  if [ -d "$FINAL_APP_PATH" ]; then
    print_warning "${APP_NAME}.app already exists in Applications folder"
    read -p "Replace it? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      print_info "Installation cancelled"
      print_info "Extracted app location: $APP_PATH"
      TEMP_DIR=""  # Don't cleanup so user can access the app
      exit 0
    fi
    print_info "Removing existing app..."
    rm -rf "$FINAL_APP_PATH"
  fi

  print_info "Moving to Applications folder..."
  if mv "$APP_PATH" "$FINAL_APP_PATH" 2>/dev/null; then
    print_success "Moved to /Applications/"
    APP_LOCATION="$FINAL_APP_PATH"
    # Temp directory will be cleaned up automatically since we moved the app out
  else
    print_error "Failed to move to Applications folder (permission denied)"
    print_warning "Your user account may not have admin privileges"
    print_info "You can move manually:"
    print_info "  sudo mv \"$APP_PATH\" /Applications/"
    print_info "Or move without sudo to a location you own:"
    print_info "  mv \"$APP_PATH\" ~/Applications/"
    TEMP_DIR=""  # Don't cleanup so user can access the app
    exit 1
  fi
else
  print_info "App not moved to Applications (use --move-to-applications to enable)"
  APP_LOCATION="$APP_PATH"
  TEMP_DIR=""  # Don't cleanup so user can access the app
fi

# Clean up downloaded ZIP
if [ -f "$ZIP_PATH" ]; then
  print_info "Cleaning up downloaded ZIP file..."
  rm "$ZIP_PATH"
fi

# Success message
echo ""
print_success "Installation complete!"
echo ""
print_info "App location:"
echo "  ${APP_LOCATION}"
echo ""
if [ "$MOVE_TO_APPLICATIONS" = true ]; then
  print_info "To launch:"
  echo "  1. Open Applications folder"
  echo "  2. Double-click ${APP_NAME}"
  if [ "$REMOVE_QUARANTINE" = false ]; then
    echo "  3. On first launch, right-click and select 'Open' (unsigned app)"
  fi
else
  print_info "Next steps:"
  echo "  1. Move to Applications: mv \"${APP_LOCATION}\" /Applications/"
  if [ "$REMOVE_QUARANTINE" = false ]; then
    echo "  2. On first launch, right-click and select 'Open' (unsigned app)"
  else
    echo "  2. Launch from Applications folder"
  fi
fi
echo ""

# Check if gh is installed and authenticated
if ! command -v gh &> /dev/null || ! gh auth status &> /dev/null; then
  print_warning "Don't forget to set up GitHub CLI:"
  echo "  brew install gh"
  echo "  gh auth login"
  echo ""
fi

print_success "Enjoy! 🚀"
echo ""
