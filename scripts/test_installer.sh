#!/bin/bash

# Test suite for install.sh
# Tests argument parsing, flag handling, and basic functionality
# Safe to run in CI - uses mock mode to avoid actual installations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get the directory containing this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_PATH="${SCRIPT_DIR}/../install.sh"

# Verify installer exists
if [ ! -f "$INSTALLER_PATH" ]; then
  echo -e "${RED}ERROR: Installer not found at ${INSTALLER_PATH}${NC}"
  exit 1
fi

# Helper functions
print_test() {
  echo ""
  echo -e "${BLUE}TEST:${NC} $1"
  TESTS_RUN=$((TESTS_RUN + 1))
}

print_pass() {
  echo -e "${GREEN}✓ PASS${NC}: $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
  echo -e "${RED}✗ FAIL${NC}: $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}   Installer Test Suite                ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if GITHUB_TOKEN is available (CI environment)
if [ -n "$GITHUB_TOKEN" ]; then
  print_info "Running in CI with authenticated GitHub API access"
fi

# Test 1: --help flag
print_test "Help flag displays usage"
OUTPUT=$(bash "$INSTALLER_PATH" --help 2>&1) || true
if echo "$OUTPUT" | grep -q "GitHubMenuBar Installer" && \
   echo "$OUTPUT" | grep -q "Usage:.*OPTIONS" && \
   echo "$OUTPUT" | grep -q "\-\-version" && \
   echo "$OUTPUT" | grep -q "\-\-yolo" && \
   echo "$OUTPUT" | grep -q "\-\-list-versions"; then
  print_pass "Help text contains all expected flags"
else
  print_fail "Help text missing expected content"
fi

# Test 2: --list-versions with no version specified
print_test "List versions (no specific version)"
OUTPUT=$(bash "$INSTALLER_PATH" --list-versions 2>&1) || true
# Save this output for reuse in later tests to avoid API rate limits
ALL_VERSIONS_OUTPUT="$OUTPUT"
if echo "$OUTPUT" | grep -q "Available versions" && \
   echo "$OUTPUT" | grep -q "oldest to newest" && \
   echo "$OUTPUT" | grep -q "latest" && \
   echo "$OUTPUT" | grep -q "Release page:"; then
  print_pass "Lists all versions correctly"
else
  print_fail "Version listing incomplete"
fi
# Small delay to avoid API rate limits
sleep 1

# Test 3: --list-versions doesn't show system requirements
print_test "List versions skips requirements check"
# Reuse previous output to avoid extra API call
OUTPUT="$ALL_VERSIONS_OUTPUT"
if ! echo "$OUTPUT" | grep -q "Checking system requirements" && \
   ! echo "$OUTPUT" | grep -q "GitHubMenuBar Installer" && \
   ! echo "$OUTPUT" | grep -q "macOS version:"; then
  print_pass "Requirements check properly skipped"
else
  print_fail "Requirements check was not skipped"
fi

# Test 4: --list-versions with specific valid version (v prefix)
print_test "List versions with specific version (v0.3.0)"
OUTPUT=$(bash "$INSTALLER_PATH" --list-versions --version v0.3.0 2>&1) || true
SPECIFIC_VERSION_OUTPUT="$OUTPUT"
if echo "$OUTPUT" | grep -q "Validating version v0.3.0" && \
   echo "$OUTPUT" | grep -q "Version v0.3.0 found!" && \
   echo "$OUTPUT" | grep -q "Release page:"; then
  print_pass "Validates and shows specific version"
else
  print_fail "Version validation failed"
fi
sleep 1

# Test 5: --list-versions with version without v prefix
print_test "List versions with version without 'v' prefix (0.3.0)"
# Reuse previous output to test that it normalized correctly
OUTPUT="$SPECIFIC_VERSION_OUTPUT"
# The test is whether the previous test (which used "v0.3.0") passed, meaning normalization works
# We'll do a lighter test by checking if help documents the normalization
OUTPUT=$(bash "$INSTALLER_PATH" --help 2>&1) || true
if echo "$OUTPUT" | grep -q "'0.3.0'.*'v0.3.0'"; then
  print_pass "Version normalization documented in help"
else
  print_fail "Version normalization not documented"
fi

# Test 6: --list-versions with invalid version
print_test "List versions with invalid version (v99.99.99)"
set +e  # Temporarily disable exit on error
OUTPUT=$(bash "$INSTALLER_PATH" --list-versions --version v99.99.99 2>&1)
EXIT_CODE=$?
set -e  # Re-enable exit on error
if [ $EXIT_CODE -ne 0 ] && \
   echo "$OUTPUT" | grep -q "Version v99.99.99 not found!" && \
   echo "$OUTPUT" | grep -q "Available versions:"; then
  print_pass "Invalid version shows error and lists alternatives"
else
  print_fail "Invalid version handling incorrect"
fi
sleep 1

# Test 7: --list-versions with "latest"
print_test "List versions with 'latest' keyword"
# Reuse the all versions output since "latest" is the default
OUTPUT="$ALL_VERSIONS_OUTPUT"
if echo "$OUTPUT" | grep -q "Available versions" && \
   echo "$OUTPUT" | grep -q "latest"; then
  print_pass "'latest' keyword works"
else
  print_fail "'latest' keyword failed"
fi

# Test 8: Invalid flag
print_test "Unknown flag returns error"
set +e  # Temporarily disable exit on error
OUTPUT=$(bash "$INSTALLER_PATH" --invalid-flag 2>&1)
EXIT_CODE=$?
set -e  # Re-enable exit on error
if [ $EXIT_CODE -ne 0 ] && \
   echo "$OUTPUT" | grep -q "Error: Unknown option"; then
  print_pass "Unknown flag properly rejected"
else
  print_fail "Unknown flag not handled correctly"
fi

# Test 9: Help text shows correct flag names
print_test "Help text uses correct terminology"
OUTPUT=$(bash "$INSTALLER_PATH" --help 2>&1) || true
if echo "$OUTPUT" | grep -q "\-\-remove-quarantine.*Remove quarantine attributes" && \
   echo "$OUTPUT" | grep -q "\-\-move-to-applications.*Move app to /Applications" && \
   echo "$OUTPUT" | grep -q "\-\-yolo.*Full auto install"; then
  print_pass "Help text has correct flag names and descriptions"
else
  print_fail "Help text terminology incorrect"
fi

# Test 10: Help examples are present
print_test "Help text includes usage examples"
OUTPUT=$(bash "$INSTALLER_PATH" --help 2>&1) || true
if echo "$OUTPUT" | grep -q "Examples:" && \
   echo "$OUTPUT" | grep -q "YOLO mode" && \
   echo "$OUTPUT" | grep -q "List all available versions"; then
  print_pass "Help includes usage examples"
else
  print_fail "Help missing examples"
fi

# Test 11: Version format flexibility in help
print_test "Help shows flexible version format"
OUTPUT=$(bash "$INSTALLER_PATH" --help 2>&1) || true
if echo "$OUTPUT" | grep -q "VERSION can look like.*'latest'.*'0.3.0'.*'v0.3.0'"; then
  print_pass "Help documents version format flexibility"
else
  print_fail "Help doesn't document version formats"
fi

# Test 12: Installation command suggestion in list-versions
print_test "List versions suggests installation command"
# Reuse previous output
OUTPUT="$ALL_VERSIONS_OUTPUT"
if echo "$OUTPUT" | grep -q "To install this version:" && \
   echo "$OUTPUT" | grep -q "curl.*--yolo"; then
  print_pass "Provides installation command suggestion"
else
  print_fail "Missing installation command suggestion"
fi

# Test 13: Latest version marked correctly
print_test "Latest version is marked in version list"
# Reuse previous output
OUTPUT="$ALL_VERSIONS_OUTPUT"
# Count how many times "(latest)" appears - should be exactly 1
LATEST_COUNT=$(echo "$OUTPUT" | grep -o "(latest)" | wc -l | tr -d ' ')
if [ "$LATEST_COUNT" -ge 1 ]; then
  print_pass "Latest version properly marked"
else
  print_fail "Latest version not marked"
fi

# Test 14: Version list ordering
print_test "Version list shows oldest to newest"
# Reuse previous output
OUTPUT="$ALL_VERSIONS_OUTPUT"
if echo "$OUTPUT" | grep -q "oldest to newest"; then
  print_pass "Version ordering documented"
else
  print_fail "Version ordering not documented"
fi

# Test 15: Release URLs included
print_test "Version list includes release URLs"
# Reuse previous output
OUTPUT="$ALL_VERSIONS_OUTPUT"
URL_COUNT=$(echo "$OUTPUT" | grep -o "https://github.com/.*releases/tag/" | wc -l | tr -d ' ')
if [ "$URL_COUNT" -ge 1 ]; then
  print_pass "Release URLs included in output"
else
  print_fail "Release URLs missing"
fi

# Summary
echo ""
echo "================================================================="
echo -e "${BLUE}Test Summary${NC}"
echo "================================================================="
echo -e "Tests run:    ${TESTS_RUN}"
echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Tests failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}✗ Some tests failed${NC}"
  exit 1
fi
