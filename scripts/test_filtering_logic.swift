#!/usr/bin/env swift

// Test to verify the corrected filtering logic handles draft PRs properly

struct TestPR {
    let title: String
    let state: String
    let isDraft: Bool
}

// Simulate test PRs matching your actual data
let testPRs: [TestPR] = [
    TestPR(title: "Open non-draft PR", state: "open", isDraft: false),
    TestPR(title: "Merged PR", state: "merged", isDraft: false),
    TestPR(title: "Closed non-draft PR", state: "closed", isDraft: false),
    TestPR(title: "Closed draft PR #1", state: "closed", isDraft: true),
    TestPR(title: "Closed draft PR #2", state: "closed", isDraft: true),
]

// Test configuration: Open + Closed (exclude Draft + Merged)
let hasOpen = true
let hasDraft = false  // EXCLUDED
let hasMerged = false  // EXCLUDED
let hasClosed = true

print("Filter configuration: Open=\(hasOpen), Draft=\(hasDraft), Merged=\(hasMerged), Closed=\(hasClosed)")
print()

print("OLD LOGIC (buggy):")
print("==================")
for pr in testPRs {
    let result: Bool
    switch pr.state.lowercased() {
    case "open":
        if pr.isDraft {
            result = hasDraft
        } else {
            result = hasOpen
        }
    case "merged":
        result = hasMerged
    case "closed":
        result = hasClosed  // BUG: doesn't check isDraft!
    default:
        result = false
    }

    print("\(pr.title): state=\(pr.state), isDraft=\(pr.isDraft) -> \(result ? "KEEP" : "FILTER")")
}

print()
print("NEW LOGIC (fixed):")
print("==================")
for pr in testPRs {
    let result: Bool
    // First check draft status (applies to both open and closed PRs)
    if pr.isDraft {
        result = hasDraft
    } else {
        // Non-draft PRs: check state
        switch pr.state.lowercased() {
        case "open":
            result = hasOpen
        case "merged":
            result = hasMerged
        case "closed":
            result = hasClosed
        default:
            result = false
        }
    }

    print("\(pr.title): state=\(pr.state), isDraft=\(pr.isDraft) -> \(result ? "KEEP" : "FILTER")")
}

print()
print("Expected result: Keep 2 PRs (Open non-draft + Closed non-draft)")
