#!/bin/bash
set -e

ISSUE_TITLE="${ISSUE_TITLE:-Test Issue for Orchestration}"
ISSUE_DESCRIPTION="${ISSUE_DESCRIPTION:-This is a test issue created for orchestration testing. It simulates a realistic td issue with proper title and description.}"
ISSUE_PRIORITY="${ISSUE_PRIORITY:-P2}"

log() {
    echo "[setup-test-issue] $1"
}

create_test_issue() {
    log "Creating test td issue..."
    
    local issue_id
    issue_id=$(td add "$ISSUE_TITLE" \
        --description "$ISSUE_DESCRIPTION" \
        --priority "$ISSUE_PRIORITY" \
        --minor \
        2>&1 | grep -oP 'td-[a-f0-9]+' | head -1)
    
    if [ -z "$issue_id" ]; then
        log "Failed to create issue"
        return 1
    fi
    
    log "Created issue: $issue_id"
    echo "$issue_id"
}

main() {
    log "Setting up test issue for orchestration testing"
    log "Configuration:"
    log "  TITLE: ${ISSUE_TITLE}"
    log "  PRIORITY: ${ISSUE_PRIORITY}"
    
    local issue_id
    issue_id=$(create_test_issue)
    
    if [ -n "$issue_id" ]; then
        log "Test issue ready: $issue_id"
        log "Use this ID in TUI: $issue_id"
        echo ""
        echo "ISSUE_ID=$issue_id"
    else
        log "Failed to create test issue"
        exit 1
    fi
}

main "$@"
