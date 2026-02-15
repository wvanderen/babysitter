#!/bin/bash
set -e

RESPONSE_DELAY="${RESPONSE_DELAY:-2}"
RESPONSE_TYPE="${RESPONSE_TYPE:-success}"
OUTPUT_FILE="${OUTPUT_FILE:-/tmp/mock_agent_output.txt}"

log() {
    echo "[mock-agent] $1"
}

send_completion() {
    local status="$1"
    local output="$2"
    
    echo "---STAGE-COMPLETE---" >> "$OUTPUT_FILE"
    echo "STATUS: $status" >> "$OUTPUT_FILE"
    echo "OUTPUT: $output" >> "$OUTPUT_FILE"
    echo "---END---" >> "$OUTPUT_FILE"
    
    log "Stage complete: $status"
}

simulate_response() {
    log "Waiting ${RESPONSE_DELAY}s before responding..."
    sleep "$RESPONSE_DELAY"
    
    case "$RESPONSE_TYPE" in
        success)
            log "Simulating successful agent response"
            send_completion "success" "Mock agent completed task successfully"
            ;;
        failure)
            log "Simulating failed agent response"
            send_completion "failure" "Mock agent encountered an error"
            ;;
        timeout)
            log "Simulating timeout (will not send completion)"
            sleep 300
            ;;
        *)
            log "Unknown response type: $RESPONSE_TYPE"
            send_completion "failure" "Unknown response type configured"
            ;;
    esac
}

main() {
    log "Starting mock agent"
    log "Configuration:"
    log "  RESPONSE_DELAY: ${RESPONSE_DELAY}s"
    log "  RESPONSE_TYPE: ${RESPONSE_TYPE}"
    log "  OUTPUT_FILE: ${OUTPUT_FILE}"
    
    rm -f "$OUTPUT_FILE"
    touch "$OUTPUT_FILE"
    
    log "Ready to receive prompts"
    log "Send input to this tmux pane to simulate agent receiving work"
    
    simulate_response
}

main "$@"
