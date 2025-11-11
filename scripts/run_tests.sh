#!/bin/bash

# GitHubMenuBar Test Script
# Runs all tests including unit tests and installer tests

set -e  # Exit on error

echo "🧪 Running test suite..."

# Run Swift unit tests
echo "📝 Running Swift unit tests..."
swift test
if [ $? -ne 0 ]; then
  echo "❌ Swift tests failed!"
  exit 1
fi
echo "✅ Swift tests passed"

# Run installer tests
echo "📦 Running installer tests..."
if [ -f "scripts/test_installer.sh" ]; then
  chmod +x scripts/test_installer.sh
  ./scripts/test_installer.sh
  if [ $? -ne 0 ]; then
    echo "❌ Installer tests failed!"
    exit 1
  fi
  echo "✅ Installer tests passed"
else
  echo "⚠️  Warning: Installer tests not found at scripts/test_installer.sh"
fi

echo ""
echo "✅ All tests passed!"
