#!/bin/bash

# Comprehensive test of all 16 filter combinations
# Tests both the gh CLI calls AND the expected client-side filtering results

set -e

echo "================================================================================"
echo "Testing All 16 Filter Combinations"
echo "================================================================================"
echo ""

# First, get baseline data with no filters
echo "BASELINE: Fetching all PRs to understand what we have..."
echo "------------------------------------------------------------------------"
ALL_PRS=$(gh search prs --review-requested=@me --json id,title,number,repository,state,isDraft --limit 50)

total=$(echo "$ALL_PRS" | jq '. | length')
open_non_draft=$(echo "$ALL_PRS" | jq '[.[] | select(.state == "open" and .isDraft == false)] | length')
open_draft=$(echo "$ALL_PRS" | jq '[.[] | select(.state == "open" and .isDraft == true)] | length')
merged=$(echo "$ALL_PRS" | jq '[.[] | select(.state == "merged")] | length')
closed_non_draft=$(echo "$ALL_PRS" | jq '[.[] | select(.state == "closed" and .isDraft == false)] | length')
closed_draft=$(echo "$ALL_PRS" | jq '[.[] | select(.state == "closed" and .isDraft == true)] | length')

echo "Total PRs: $total"
echo "  - Open (non-draft): $open_non_draft"
echo "  - Open (draft):     $open_draft"
echo "  - Merged:           $merged"
echo "  - Closed (non-draft): $closed_non_draft"
echo "  - Closed (draft):   $closed_draft"
echo ""

# Function to test a specific filter combination
test_combination() {
    local combo_name="$1"
    local has_open="$2"
    local has_draft="$3"
    local has_merged="$4"
    local has_closed="$5"

    echo "================================================================================"
    echo "TEST: $combo_name"
    echo "  Included: Open=$has_open, Draft=$has_draft, Merged=$has_merged, Closed=$has_closed"
    echo "================================================================================"

    # Calculate expected count using client-side filtering logic
    expected=$(echo "$ALL_PRS" | jq --argjson open "$has_open" --argjson draft "$has_draft" --argjson merged "$has_merged" --argjson closed "$has_closed" '
        [.[] | select(
            if .isDraft then
                $draft
            else
                (.state == "open" and $open) or
                (.state == "merged" and $merged) or
                (.state == "closed" and $closed)
            end
        )] | length
    ')

    echo "EXPECTED count (based on client-side filtering): $expected"
    echo ""

    # Determine what gh command should be used
    local cmd_args="--review-requested=@me"
    local needs_client_filter=false

    if [ "$has_draft" = "true" ]; then
        # When draft is included, can't use --state flags
        echo "Command strategy: Fetch all (draft can be in any state), use client-side filter"
        needs_client_filter=true
    else
        # No drafts wanted, can use --draft=false
        cmd_args="$cmd_args --draft=false"

        if [ "$has_open" = "true" ] && [ "$has_merged" = "false" ] && [ "$has_closed" = "false" ]; then
            cmd_args="$cmd_args --state=open"
            echo "Command strategy: gh search prs $cmd_args"
            needs_client_filter=false
        elif [ "$has_open" = "false" ] && { [ "$has_merged" = "true" ] || [ "$has_closed" = "true" ]; }; then
            cmd_args="$cmd_args --state=closed"
            echo "Command strategy: gh search prs $cmd_args (will need client filter for merged vs closed)"
            needs_client_filter=true
        else
            echo "Command strategy: gh search prs $cmd_args (mixed, needs client-side filter)"
            needs_client_filter=true
        fi
    fi

    # Execute the gh command
    echo ""
    echo "Executing: gh search prs $cmd_args --json id,state,isDraft --limit 50"
    result=$(gh search prs $cmd_args --json id,state,isDraft --limit 50)

    # Count what gh returned
    gh_count=$(echo "$result" | jq '. | length')
    echo "gh returned: $gh_count PRs"

    # Apply client-side filtering if needed
    if [ "$needs_client_filter" = "true" ]; then
        filtered_count=$(echo "$result" | jq --argjson open "$has_open" --argjson draft "$has_draft" --argjson merged "$has_merged" --argjson closed "$has_closed" '
            [.[] | select(
                if .isDraft then
                    $draft
                else
                    (.state == "open" and $open) or
                    (.state == "merged" and $merged) or
                    (.state == "closed" and $closed)
                end
            )] | length
        ')
        echo "After client-side filter: $filtered_count PRs"

        if [ "$filtered_count" = "$expected" ]; then
            echo "✓ PASS: Matches expected count"
        else
            echo "✗ FAIL: Expected $expected, got $filtered_count"
        fi
    else
        if [ "$gh_count" = "$expected" ]; then
            echo "✓ PASS: Matches expected count"
        else
            echo "✗ FAIL: Expected $expected, got $gh_count"
        fi
    fi

    echo ""
}

# Test all 16 combinations
# Format: name, hasOpen, hasDraft, hasMerged, hasClosed

test_combination "1. NONE (empty filter)" false false false false
test_combination "2. Open only" true false false false
test_combination "3. Draft only" false true false false
test_combination "4. Merged only" false false true false
test_combination "5. Closed only" false false false true
test_combination "6. Open + Draft" true true false false
test_combination "7. Open + Merged" true false true false
test_combination "8. Open + Closed" true false false true
test_combination "9. Draft + Merged" false true true false
test_combination "10. Draft + Closed" false true false true
test_combination "11. Merged + Closed" false false true true
test_combination "12. Open + Draft + Merged" true true true false
test_combination "13. Open + Draft + Closed" true true false true
test_combination "14. Open + Merged + Closed" true false true true
test_combination "15. Draft + Merged + Closed" false true true true
test_combination "16. ALL (Open + Draft + Merged + Closed)" true true true true

echo "================================================================================"
echo "Test Complete"
echo "================================================================================"
