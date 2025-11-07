#!/bin/bash

# Test script to verify gh CLI behavior with different filter combinations
# This will help us understand what gh actually returns for each filter state

set -e

echo "==================================================================="
echo "Testing gh CLI Filter Behavior"
echo "==================================================================="
echo ""

# Helper function to run gh command and summarize results
test_gh_command() {
    local description="$1"
    local command="$2"

    echo "-------------------------------------------------------------------"
    echo "TEST: $description"
    echo "COMMAND: $command"
    echo "-------------------------------------------------------------------"

    # Run the command and parse results
    result=$(eval "$command" 2>&1) || {
        echo "ERROR: Command failed"
        echo "$result"
        echo ""
        return
    }

    # Count total PRs
    total=$(echo "$result" | jq '. | length')
    echo "Total PRs returned: $total"

    # Break down by status
    if [ "$total" -gt 0 ]; then
        echo ""
        echo "Breakdown by state and isDraft:"

        open_non_draft=$(echo "$result" | jq '[.[] | select(.state == "open" and .isDraft == false)] | length')
        open_draft=$(echo "$result" | jq '[.[] | select(.state == "open" and .isDraft == true)] | length')
        merged=$(echo "$result" | jq '[.[] | select(.state == "merged")] | length')
        closed=$(echo "$result" | jq '[.[] | select(.state == "closed")] | length')

        echo "  - OPEN (non-draft): $open_non_draft"
        echo "  - OPEN (draft):     $open_draft"
        echo "  - MERGED:           $merged"
        echo "  - CLOSED:           $closed"

        # Show first few PRs as examples
        echo ""
        echo "Sample PRs:"
        echo "$result" | jq -r '.[:3] | .[] | "  - \(.repository.nameWithOwner) #\(.number): \(.title) [state=\(.state), isDraft=\(.isDraft)]"'
    fi

    echo ""
}

# Base command
BASE_CMD='gh search prs --review-requested=@me --json id,title,number,repository,state,isDraft --limit 50'

echo "Testing different --state flag combinations..."
echo ""

# Test 1: No state filter (should return everything)
test_gh_command \
    "No state filter (baseline - all PRs)" \
    "$BASE_CMD"

# Test 2: Only --state=open
test_gh_command \
    "Only --state=open (should include both draft and non-draft open PRs)" \
    "$BASE_CMD --state=open"

# Test 3: Only --state=closed
test_gh_command \
    "Only --state=closed (should include both merged and closed PRs)" \
    "$BASE_CMD --state=closed"

# Test 4: Try multiple --state flags (likely not supported)
test_gh_command \
    "Multiple --state flags: --state=open --state=closed (testing if supported)" \
    "$BASE_CMD --state=open --state=closed"

# Test 5: Check if draft filter exists
test_gh_command \
    "Testing --draft flag (if it exists)" \
    "$BASE_CMD --draft"

# Test 6: Testing --draft=true
test_gh_command \
    "Testing --draft=true (if it exists)" \
    "$BASE_CMD --draft=true"

# Test 7: Testing --draft=false
test_gh_command \
    "Testing --draft=false (if it exists)" \
    "$BASE_CMD --draft=false"

echo "==================================================================="
echo "Test Summary Complete"
echo "==================================================================="
echo ""
echo "Key findings to check:"
echo "1. Does --state=open return BOTH draft and non-draft PRs?"
echo "2. Does --state=closed return BOTH merged and closed PRs?"
echo "3. Can we use multiple --state flags?"
echo "4. Is there a --draft flag we can use?"
echo ""
echo "Based on these results, we'll know which filters need client-side"
echo "handling vs which can be done with gh CLI flags."
