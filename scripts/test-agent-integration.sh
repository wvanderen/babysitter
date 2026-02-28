#!/bin/bash
#
# Agent Integration Test Runner
# Runs the agent orchestration integration test workflow
#
# Usage:
#   ./scripts/test-agent-integration.sh [options]
#
# Options:
#   --api       Run via API (requires daemon running)
#   --tui       Run via TUI (default)
#   --help      Show this help message
#
# Requirements:
#   - Babysitter daemon running (for --api)
#   - pi agent installed and configured
#   - tmux available

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORKFLOW_FILE="$PROJECT_ROOT/.babysitter/workflows/test-agent.yaml"

run_via_tui() {
    echo "Running agent integration test via TUI..."
    
    if [ ! -f "$WORKFLOW_FILE" ]; then
        echo "ERROR: Workflow file not found: $WORKFLOW_FILE"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
    
    if [ -f "./priv/babysitter-tui" ]; then
        ./priv/babysitter-tui --workflow test-agent
    elif command -v babysitter-tui &> /dev/null; then
        babysitter-tui --workflow test-agent
    else
        echo "ERROR: babysitter-tui not found"
        echo "Build it with: cd go && go build -o ../priv/babysitter-tui ./cmd/babysitter-tui"
        exit 1
    fi
}

run_via_api() {
    echo "Running agent integration test via API..."
    
    local API_URL="${BABYSITTER_API_URL:-http://localhost:4001}"
    local SESSION_ID="test-agent-$(date +%s)"
    
    if [ ! -f "$WORKFLOW_FILE" ]; then
        echo "ERROR: Workflow file not found: $WORKFLOW_FILE"
        exit 1
    fi
    
    echo "Creating session: $SESSION_ID"
    
    RESPONSE=$(curl -s -X POST "$API_URL/api/sessions" \
        -H "Content-Type: application/json" \
        -d "{\"id\": \"$SESSION_ID\", \"workflow_id\": \"test-agent\"}")
    
    if echo "$RESPONSE" | grep -q "error"; then
        echo "ERROR: Failed to create session"
        echo "$RESPONSE"
        exit 1
    fi
    
    echo "Starting workflow..."
    
    curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/start" \
        -H "Content-Type: application/json"
    
    echo ""
    echo "Test started. Monitor progress at:"
    echo "  $API_URL/api/sessions/$SESSION_ID"
    echo ""
    echo "Or connect via WebSocket:"
    echo "  ws://localhost:4001/socket/websocket"
    echo "  Topic: session:$SESSION_ID"
}

show_help() {
    head -20 "$0" | tail -18 | sed 's/^#//'
    exit 0
}

case "${1:-}" in
    --api)
        run_via_api
        ;;
    --tui)
        run_via_tui
        ;;
    --help|-h)
        show_help
        ;;
    *)
        run_via_tui
        ;;
esac
