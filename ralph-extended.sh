#!/bin/bash
# Ralph Extended - Multi-agent autonomous coding system
# Usage: ./ralph-extended.sh [--tool amp|claude] [max_iterations]

set -e

# Parse arguments
TOOL="claude"  # Default to claude for extended version
MAX_ITERATIONS=20
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

# Validate tool choice
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'."
  exit 1
fi

# File paths
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
FEATURE_PROGRESS_FILE="$SCRIPT_DIR/feature_progress.json"
ARCHIVE_DIR="$SCRIPT_DIR/archive"

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Extended Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Initialize feature_progress.json if it doesn't exist
if [ ! -f "$FEATURE_PROGRESS_FILE" ]; then
  echo "feature_progress.json not found. Creating from prd.json..."

  # Check if prd.json exists
  if [ ! -f "$PRD_FILE" ]; then
    echo "Error: prd.json not found. Please create prd.json first."
    exit 1
  fi

  # Extract user stories from prd.json and create feature_progress.json
  jq '{
    currentFeature: (.userStories[0].id // "none"),
    features: (.userStories | map({
      (.id): {
        state: "pending",
        reviewCycleCount: 0,
        history: [],
        currentIssues: []
      }
    }) | add),
    config: {
      maxReviewCycles: 5,
      skipReviewAfterMax: true,
      maxQACycles: 5,
      skipQAAfterMax: true
    }
  } | .features[.currentFeature].state = "backend_dev"' "$PRD_FILE" > "$FEATURE_PROGRESS_FILE"

  echo "Created feature_progress.json with $(jq '.userStories | length' "$PRD_FILE") features"
  echo "Starting with feature: $(jq -r '.currentFeature' "$FEATURE_PROGRESS_FILE")"
fi

# Function to get current state from feature_progress.json
get_current_state() {
  jq -r '.features[.currentFeature].state // "none"' "$FEATURE_PROGRESS_FILE"
}

# Function to get current feature ID
get_current_feature() {
  jq -r '.currentFeature // "none"' "$FEATURE_PROGRESS_FILE"
}

# Function to get review cycle count
get_review_cycle_count() {
  local feature_id=$(get_current_feature)
  jq -r ".features[\"$feature_id\"].reviewCycleCount // 0" "$FEATURE_PROGRESS_FILE"
}

# Function to increment review cycle count
increment_review_cycle() {
  local feature_id=$(get_current_feature)
  local current_count=$(get_review_cycle_count)
  local new_count=$((current_count + 1))

  # Update the review cycle count in feature_progress.json
  jq ".features[\"$feature_id\"].reviewCycleCount = $new_count" "$FEATURE_PROGRESS_FILE" > "$FEATURE_PROGRESS_FILE.tmp"
  mv "$FEATURE_PROGRESS_FILE.tmp" "$FEATURE_PROGRESS_FILE"

  echo "Review cycle: $new_count"
}

# Function to spawn agent based on state
spawn_agent() {
  local state=$1
  local prompt_file=""
  local agent_name=""

  case $state in
    backend_dev|backend_review_failed)
      prompt_file="$SCRIPT_DIR/agents/BACKEND_DEV.md"
      agent_name="Backend Developer"
      ;;
    backend_review)
      prompt_file="$SCRIPT_DIR/agents/BACKEND_REVIEWER.md"
      agent_name="Backend Reviewer"
      ;;
    frontend_dev|frontend_review_failed)
      prompt_file="$SCRIPT_DIR/agents/FRONTEND_DEV.md"
      agent_name="Frontend Developer"
      ;;
    frontend_review)
      prompt_file="$SCRIPT_DIR/agents/FRONTEND_REVIEWER.md"
      agent_name="Frontend Reviewer"
      ;;
    qa_testing)
      prompt_file="$SCRIPT_DIR/agents/QA.md"
      agent_name="QA Engineer"
      ;;
    qa_issues_backend)
      prompt_file="$SCRIPT_DIR/agents/BACKEND_DEV.md"
      agent_name="Backend Developer (QA Fixes)"
      ;;
    qa_issues_frontend)
      prompt_file="$SCRIPT_DIR/agents/FRONTEND_DEV.md"
      agent_name="Frontend Developer (QA Fixes)"
      ;;
    qa_passed)
      echo "QA phase complete! Feature ready for deployment."
      return 0
      ;;
    frontend_review_passed)
      echo "Frontend phase complete! Auto-transitioning to QA."
      return 0
      ;;
    *)
      echo "Error: Unknown state '$state'"
      return 1
      ;;
  esac

  echo "Spawning: $agent_name"
  echo "State: $state"

  # Check if project has CLAUDE.md for project-specific context
  PROJECT_CLAUDE="CLAUDE.md"

  if [[ "$TOOL" == "amp" ]]; then
    if [ -f "$PROJECT_CLAUDE" ]; then
      OUTPUT=$(cat "$PROJECT_CLAUDE" "$prompt_file" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
    else
      OUTPUT=$(cat "$prompt_file" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
    fi
  else
    # Claude Code: use --dangerously-skip-permissions for autonomous operation, --print for output
    if [ -f "$PROJECT_CLAUDE" ]; then
      echo "Using project CLAUDE.md for context"
      OUTPUT=$(cat "$PROJECT_CLAUDE" "$prompt_file" | claude --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
    else
      OUTPUT=$(cat "$prompt_file" | claude --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
    fi
  fi

  echo "$OUTPUT"
}

# Function to determine next state based on agent output
determine_next_state() {
  local output=$1

  # Backend states
  if echo "$output" | grep -q "BACKEND_DEV_COMPLETE"; then
    echo "backend_review"
  elif echo "$output" | grep -q "BACKEND_NO_WORK"; then
    echo "backend_review_passed"
  elif echo "$output" | grep -q "BACKEND_REVIEW_PASSED"; then
    echo "backend_review_passed"
  elif echo "$output" | grep -q "BACKEND_REVIEW_FAILED"; then
    # Increment review cycle count before going back to dev
    increment_review_cycle
    echo "backend_review_failed"
  elif echo "$output" | grep -q "BACKEND_REVIEW_PASSED_NO_WORK"; then
    echo "backend_review_passed"
  elif echo "$output" | grep -q "BACKEND_REVIEW_PASSED_MAX_CYCLES"; then
    echo "backend_review_passed"
  # Frontend states
  elif echo "$output" | grep -q "FRONTEND_DEV_COMPLETE"; then
    echo "frontend_review"
  elif echo "$output" | grep -q "FRONTEND_NO_WORK"; then
    echo "frontend_review_passed"
  elif echo "$output" | grep -q "FRONTEND_REVIEW_PASSED"; then
    echo "frontend_review_passed"
  elif echo "$output" | grep -q "FRONTEND_REVIEW_FAILED"; then
    # Increment review cycle count before going back to dev
    increment_review_cycle
    echo "frontend_review_failed"
  elif echo "$output" | grep -q "FRONTEND_REVIEW_PASSED_NO_WORK"; then
    echo "frontend_review_passed"
  elif echo "$output" | grep -q "FRONTEND_REVIEW_PASSED_MAX_CYCLES"; then
    echo "frontend_review_passed"
  # QA states
  elif echo "$output" | grep -q "QA_TESTING_COMPLETE"; then
    echo "qa_passed"
  elif echo "$output" | grep -q "QA_NO_TESTING"; then
    echo "qa_passed"
  elif echo "$output" | grep -q "QA_ISSUES_BACKEND"; then
    increment_review_cycle
    echo "qa_issues_backend"
  elif echo "$output" | grep -q "QA_ISSUES_FRONTEND"; then
    increment_review_cycle
    echo "qa_issues_frontend"
  elif echo "$output" | grep -q "QA_PASSED_MAX_CYCLES"; then
    echo "qa_passed"
  else
    echo "unknown"
  fi
}

echo "========================================================================="
echo "  Ralph Extended - Multi-Agent System"
echo "  Tool: $TOOL"
echo "  Max iterations: $MAX_ITERATIONS"
echo "========================================================================="
echo ""

# Main loop
for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "======================================================================="
  echo "  Iteration $i of $MAX_ITERATIONS"
  echo "======================================================================="

  # Get current state
  CURRENT_STATE=$(get_current_state)
  CURRENT_FEATURE=$(get_current_feature)

  if [[ "$CURRENT_STATE" == "none" ]] || [[ "$CURRENT_FEATURE" == "none" ]]; then
    echo "Error: No current feature or state found in feature_progress.json"
    exit 1
  fi

  echo "Current feature: $CURRENT_FEATURE"
  echo "Current state: $CURRENT_STATE"

  # Check if feature is fully complete (QA passed)
  if [[ "$CURRENT_STATE" == "qa_passed" ]]; then
    echo ""
    echo "Feature $CURRENT_FEATURE fully complete!"
    echo "Backend, Frontend, and QA phases all passed."
    echo "Feature is ready for deployment."

    # Update prd.json to mark feature as complete
    echo "Updating prd.json: Setting $CURRENT_FEATURE passes=true"
    jq ".userStories |= map(if .id == \"$CURRENT_FEATURE\" then .passes = true else . end)" "$PRD_FILE" > "$PRD_FILE.tmp"
    mv "$PRD_FILE.tmp" "$PRD_FILE"

    # Check if there are more features to work on
    NEXT_FEATURE=$(jq -r '
      .features |
      to_entries |
      map(select(.value.state == "pending")) |
      sort_by(.value.priority // .key) |
      .[0].key // "none"
    ' "$FEATURE_PROGRESS_FILE")

    if [[ "$NEXT_FEATURE" != "none" ]]; then
      echo ""
      echo "Moving to next feature: $NEXT_FEATURE"
      # Update currentFeature and set new feature to backend_dev
      jq ".currentFeature = \"$NEXT_FEATURE\" | .features[\"$NEXT_FEATURE\"].state = \"backend_dev\"" "$FEATURE_PROGRESS_FILE" > "$FEATURE_PROGRESS_FILE.tmp"
      mv "$FEATURE_PROGRESS_FILE.tmp" "$FEATURE_PROGRESS_FILE"
      sleep 2
      continue
    else
      echo ""
      echo "All features complete!"
      exit 0
    fi
  fi

  # Handle auto-transition from backend to frontend
  if [[ "$CURRENT_STATE" == "backend_review_passed" ]]; then
    echo ""
    echo "Backend phase complete! Auto-transitioning to frontend development."
    # Update state to frontend_dev
    jq ".features[\"$CURRENT_FEATURE\"].state = \"frontend_dev\"" "$FEATURE_PROGRESS_FILE" > "$FEATURE_PROGRESS_FILE.tmp"
    mv "$FEATURE_PROGRESS_FILE.tmp" "$FEATURE_PROGRESS_FILE"
    echo "State updated to: frontend_dev"
    sleep 1
    continue
  fi

  # Handle auto-transition from frontend to QA
  if [[ "$CURRENT_STATE" == "frontend_review_passed" ]]; then
    echo ""
    echo "Frontend phase complete! Auto-transitioning to QA testing."
    # Update state to qa_testing
    jq ".features[\"$CURRENT_FEATURE\"].state = \"qa_testing\"" "$FEATURE_PROGRESS_FILE" > "$FEATURE_PROGRESS_FILE.tmp"
    mv "$FEATURE_PROGRESS_FILE.tmp" "$FEATURE_PROGRESS_FILE"
    echo "State updated to: qa_testing"
    sleep 1
    continue
  fi

  # Spawn appropriate agent
  AGENT_OUTPUT=$(spawn_agent "$CURRENT_STATE")

  # Determine next state based on output
  NEXT_STATE=$(determine_next_state "$AGENT_OUTPUT")

  if [[ "$NEXT_STATE" == "unknown" ]]; then
    echo "Warning: Could not determine next state from agent output."
    echo "Current state remains: $CURRENT_STATE"
    echo "This might indicate an agent error. Check the output above."
    exit 1
  fi

  echo ""
  echo "Next state: $NEXT_STATE"

  sleep 2
done

echo ""
echo "Ralph Extended reached max iterations ($MAX_ITERATIONS) without completing feature."
echo "Check $PROGRESS_FILE and $FEATURE_PROGRESS_FILE for status."
exit 1
