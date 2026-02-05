#!/bin/bash
# Ralph Extended - Multi-agent autonomous coding system
# Usage: ./ralph-extended.sh [--tool amp|claude|codex] [--model MODEL] [--no-sandbox] [max_iterations]

set -e

# Parse arguments
TOOL="claude"  # Default to claude for extended version
MAX_ITERATIONS=20
USE_DOCKER_SANDBOX=true  # Enable Docker Sandbox by default
CLAUDE_MODEL=""  # Empty means use Claude Code's default
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
    --model)
      CLAUDE_MODEL="$2"
      shift 2
      ;;
    --model=*)
      CLAUDE_MODEL="${1#*=}"
      shift
      ;;
    --no-sandbox)
      USE_DOCKER_SANDBOX=false
      shift
      ;;
    --sandbox)
      USE_DOCKER_SANDBOX=true
      shift
      ;;
    --help)
      echo "Usage: ./ralph-extended.sh [--tool amp|claude|codex] [--model MODEL] [--no-sandbox] [max_iterations]"
      echo "  --tool:       AI tool to use (amp, claude, or codex, default: claude)"
      echo "  --model:      Claude model to use (e.g., claude-sonnet-4-20250514, claude-opus-4-20250514)"
      echo "  --no-sandbox: Disable Docker sandbox isolation (runs on host)"
      echo "  --sandbox:    Enable Docker sandbox isolation (default)"
      echo "  max_iterations: Maximum number of iterations (default: 20)"
      exit 0
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
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" && "$TOOL" != "codex" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp', 'claude', or 'codex'."
  exit 1
fi

# Show auth status based on tool
if [[ "$TOOL" == "codex" ]]; then
  if [ -f "$HOME/.codex/auth.json" ]; then
    echo "Codex auth: ~/.codex/auth.json (found)"
  else
    echo "Codex auth: ~/.codex/auth.json (NOT FOUND - run 'codex login' first)"
  fi
elif [[ "$TOOL" == "claude" ]] && [[ -n "$ANTHROPIC_API_KEY" ]]; then
  echo "ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:0:10}...${ANTHROPIC_API_KEY: -4} (loaded)"
fi

# Trap to clean up sandboxes on script exit
cleanup_on_exit() {
  echo "" >&2
  echo "Cleaning up Docker sandboxes..." >&2

  # Get all sandboxes for current feature
  if [ -f "$FEATURE_PROGRESS_FILE" ]; then
    CURRENT_FEATURE=$(get_current_feature 2>/dev/null || echo "none")
    if [[ "$CURRENT_FEATURE" != "none" ]]; then
      SANDBOX_NAME=$(jq -r ".features[\"$CURRENT_FEATURE\"].sandboxName // \"null\"" "$FEATURE_PROGRESS_FILE" 2>/dev/null || echo "null")

      if [[ "$SANDBOX_NAME" != "null" ]] && [[ -n "$SANDBOX_NAME" ]]; then
        echo "Removing sandbox: $SANDBOX_NAME" >&2
        docker sandbox rm "$SANDBOX_NAME" 2>/dev/null || true
      fi
    fi
  fi
}

# Only set trap if using Docker sandbox
if [[ "$USE_DOCKER_SANDBOX" == "true" ]]; then
  trap cleanup_on_exit EXIT INT TERM
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
  # Determine initial state based on requiresBackend/requiresFrontend (default both to true)
  jq '{
    currentFeature: (.userStories[0].id // "none"),
    features: (.userStories | map({
      (.id): {
        state: "pending",
        reviewCycleCount: 0,
        history: [],
        currentIssues: [],
        sandboxName: null,
        requiresBackend: (.requiresBackend // true),
        requiresFrontend: (.requiresFrontend // true)
      }
    }) | add),
    config: {
      maxReviewCycles: 5,
      skipReviewAfterMax: true,
      maxQACycles: 5,
      skipQAAfterMax: true
    }
  }' "$PRD_FILE" > "$FEATURE_PROGRESS_FILE"

  # Set initial state for first feature based on its requirements
  FIRST_FEATURE=$(jq -r '.currentFeature' "$FEATURE_PROGRESS_FILE")
  REQUIRES_BACKEND=$(jq -r ".features[\"$FIRST_FEATURE\"].requiresBackend" "$FEATURE_PROGRESS_FILE")

  if [[ "$REQUIRES_BACKEND" == "true" ]]; then
    jq ".features[\"$FIRST_FEATURE\"].state = \"backend_dev\"" "$FEATURE_PROGRESS_FILE" > "$FEATURE_PROGRESS_FILE.tmp"
  else
    jq ".features[\"$FIRST_FEATURE\"].state = \"frontend_dev\"" "$FEATURE_PROGRESS_FILE" > "$FEATURE_PROGRESS_FILE.tmp"
  fi
  mv "$FEATURE_PROGRESS_FILE.tmp" "$FEATURE_PROGRESS_FILE"

  echo "Created feature_progress.json with $(jq '.userStories | length' "$PRD_FILE") features"
  echo "Starting with feature: $FIRST_FEATURE"
  echo "  Requires backend: $REQUIRES_BACKEND"
  echo "  Requires frontend: $(jq -r ".features[\"$FIRST_FEATURE\"].requiresFrontend" "$FEATURE_PROGRESS_FILE")"
fi

# Function to get current state from feature_progress.json
get_current_state() {
  jq -r '.features[.currentFeature].state // "none"' "$FEATURE_PROGRESS_FILE"
}

# Function to check if current feature requires backend
requires_backend() {
  local feature_id=$(get_current_feature)
  local result=$(jq -r ".features[\"$feature_id\"].requiresBackend" "$FEATURE_PROGRESS_FILE")
  # Default to true if null (jq returns "null" string for missing fields with -r)
  [[ "$result" != "false" ]]
}

# Function to check if current feature requires frontend
requires_frontend() {
  local feature_id=$(get_current_feature)
  local result=$(jq -r ".features[\"$feature_id\"].requiresFrontend" "$FEATURE_PROGRESS_FILE")
  # Default to true if null (jq returns "null" string for missing fields with -r)
  [[ "$result" != "false" ]]
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

# Function to create Docker sandbox for a feature
create_sandbox() {
  local feature_id=$1
  local sandbox_name="ralph-extended-${feature_id}"

  echo "Creating Docker sandbox: $sandbox_name" >&2

  # Check if Docker is running
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not running. Please start Docker Desktop." >&2
    exit 1
  fi

  # Check if sandbox command is available
  if ! docker sandbox --help >/dev/null 2>&1; then
    echo "ERROR: Docker sandbox command not found." >&2
    echo "Ensure Docker Desktop 4.50+ is installed with AI Sandboxes enabled." >&2
    exit 1
  fi

  # Determine sandbox template based on tool (claude or codex)
  local sandbox_template="claude"
  if [[ "$TOOL" == "codex" ]]; then
    sandbox_template="codex"
  fi

  # Check if sandbox already exists
  if docker sandbox ls 2>/dev/null | grep -q "$sandbox_name"; then
    echo "Sandbox $sandbox_name already exists, reusing it" >&2
  else
    # Create sandbox with project directory mounted
    docker sandbox create --name "$sandbox_name" "$sandbox_template" "$SCRIPT_DIR" >&2 || {
      echo "ERROR: Failed to create Docker sandbox" >&2
      echo "Ensure Docker Desktop 4.50+ is installed and running" >&2
      exit 1
    }
  fi

  # Install required dependencies in sandbox based on tool
  echo "Installing dependencies in sandbox..." >&2

  # Determine which AI tool to install
  local install_cmd=""
  if [[ "$TOOL" == "codex" ]]; then
    install_cmd="command -v codex >/dev/null 2>&1 || npm install -g @openai/codex"
  else
    install_cmd="command -v claude >/dev/null 2>&1 || npm install -g @anthropic-ai/claude-code"
  fi

  docker sandbox exec "$sandbox_name" bash -c "
    # Install AI tool
    $install_cmd

    # Install jq for JSON parsing
    command -v jq >/dev/null 2>&1 || (apt-get update && apt-get install -y jq)

    # Verify git is available (should be pre-installed)
    command -v git >/dev/null 2>&1 || (apt-get update && apt-get install -y git)

    # Configure git for sandbox use
    git config --global user.name 'Ralph Extended'
    git config --global user.email 'ralph@extended.local'
    git config --global --add safe.directory '*'
  " >&2 || {
    echo "ERROR: Failed to install dependencies in sandbox" >&2
    echo "Required tools: $TOOL, jq, git" >&2
    exit 1
  }

  # For Codex, copy auth.json from host into sandbox
  if [[ "$TOOL" == "codex" ]] && [ -f "$HOME/.codex/auth.json" ]; then
    echo "Copying Codex auth credentials into sandbox..." >&2
    # Pipe auth.json content into sandbox via stdin
    cat "$HOME/.codex/auth.json" | docker sandbox exec -i "$sandbox_name" bash -c "mkdir -p ~/.codex && cat > ~/.codex/auth.json" >&2 || {
      echo "WARNING: Failed to copy Codex auth.json into sandbox" >&2
      echo "You may need to run 'codex login' inside the sandbox" >&2
    }
  fi

  echo "Sandbox $sandbox_name ready" >&2
  echo "$sandbox_name"  # Return sandbox name to stdout
}

# Function to remove Docker sandbox
remove_sandbox() {
  local sandbox_name=$1

  echo "Removing Docker sandbox: $sandbox_name" >&2
  docker sandbox rm "$sandbox_name" 2>/dev/null || true
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

  # Check if project has context file for project-specific context
  # Use CODEX.md for codex tool, CLAUDE.md for claude tool
  PROJECT_CLAUDE="CLAUDE.md"
  PROJECT_CODEX="CODEX.md"

  if [[ "$USE_DOCKER_SANDBOX" == "true" ]]; then
    # Docker sandbox execution path
    CURRENT_FEATURE=$(get_current_feature)
    SANDBOX_NAME=$(jq -r ".features[\"$CURRENT_FEATURE\"].sandboxName // \"null\"" "$FEATURE_PROGRESS_FILE")

    # Check if auth is available for sandbox based on tool
    if [[ "$TOOL" == "codex" ]]; then
      # Codex uses browser-based auth cached in ~/.codex/auth.json
      if [ ! -f "$HOME/.codex/auth.json" ]; then
        echo "ERROR: Codex auth not found at ~/.codex/auth.json"
        echo "Please run 'codex login' on your host machine first to authenticate."
        echo ""
        echo "Or disable sandbox mode with --no-sandbox flag"
        exit 1
      fi
    elif [[ "$TOOL" == "claude" ]]; then
      if [ -z "$ANTHROPIC_API_KEY" ]; then
        echo "ERROR: ANTHROPIC_API_KEY environment variable not set."
        echo "Docker sandboxes cannot access the host's keychain."
        echo "Please export your API key before running:"
        echo "  export ANTHROPIC_API_KEY='your-api-key-here'"
        echo ""
        echo "Or disable sandbox mode with --no-sandbox flag"
        exit 1
      fi
    fi

    # Create sandbox if it doesn't exist, or reuse existing
    if [[ "$SANDBOX_NAME" == "null" ]] || [[ -z "$SANDBOX_NAME" ]]; then
      # First time for this feature - create new sandbox
      SANDBOX_NAME=$(create_sandbox "$CURRENT_FEATURE")

      # Store sandbox name in feature_progress.json
      jq ".features[\"$CURRENT_FEATURE\"].sandboxName = \"$SANDBOX_NAME\"" \
        "$FEATURE_PROGRESS_FILE" > "$FEATURE_PROGRESS_FILE.tmp"
      mv "$FEATURE_PROGRESS_FILE.tmp" "$FEATURE_PROGRESS_FILE"
    elif ! docker sandbox ls | grep -q "$SANDBOX_NAME"; then
      # Sandbox was removed (cleanup or manual deletion) - recreate it
      echo "Sandbox $SANDBOX_NAME not found, recreating..."
      SANDBOX_NAME=$(create_sandbox "$CURRENT_FEATURE")
    else
      # Sandbox exists - reuse it (for long-running features)
      echo "Reusing existing sandbox: $SANDBOX_NAME"
    fi

    echo "Using Docker sandbox: $SANDBOX_NAME"

    # Execute agent inside sandbox using docker exec with stdin
    # Pass ANTHROPIC_API_KEY to sandbox and cd to workspace directory
    if [[ "$TOOL" == "amp" ]]; then
      if [ -f "$PROJECT_CLAUDE" ]; then
        OUTPUT=$(cat "$PROJECT_CLAUDE" "$prompt_file" | \
          docker sandbox exec -i -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" "$SANDBOX_NAME" bash -c \
            "cd '$SCRIPT_DIR' && amp --dangerously-allow-all" 2>&1 | tee /dev/stderr) || true
      else
        OUTPUT=$(cat "$prompt_file" | \
          docker sandbox exec -i -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" "$SANDBOX_NAME" bash -c \
            "cd '$SCRIPT_DIR' && amp --dangerously-allow-all" 2>&1 | tee /dev/stderr) || true
      fi
    elif [[ "$TOOL" == "codex" ]]; then
      # Codex: use --dangerously-bypass-approvals-and-sandbox for autonomous operation
      # Auth is handled via ~/.codex/auth.json copied into sandbox
      if [ -f "$PROJECT_CODEX" ]; then
        echo "Using project CODEX.md for context"
        OUTPUT=$(cat "$PROJECT_CODEX" "$prompt_file" | \
          docker sandbox exec -i "$SANDBOX_NAME" bash -c \
            "cd '$SCRIPT_DIR' && codex exec --dangerously-bypass-approvals-and-sandbox" 2>&1 | tee /dev/stderr) || true
      else
        OUTPUT=$(cat "$prompt_file" | \
          docker sandbox exec -i "$SANDBOX_NAME" bash -c \
            "cd '$SCRIPT_DIR' && codex exec --dangerously-bypass-approvals-and-sandbox" 2>&1 | tee /dev/stderr) || true
      fi
    else
      # Claude Code: use --dangerously-skip-permissions for autonomous operation
      # Build model flag if specified
      MODEL_FLAG=""
      if [[ -n "$CLAUDE_MODEL" ]]; then
        MODEL_FLAG="--model $CLAUDE_MODEL"
      fi
      if [ -f "$PROJECT_CLAUDE" ]; then
        echo "Using project CLAUDE.md for context"
        OUTPUT=$(cat "$PROJECT_CLAUDE" "$prompt_file" | \
          docker sandbox exec -i -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" "$SANDBOX_NAME" bash -c \
            "cd '$SCRIPT_DIR' && claude --dangerously-skip-permissions --print $MODEL_FLAG" 2>&1 | tee /dev/stderr) || true
      else
        OUTPUT=$(cat "$prompt_file" | \
          docker sandbox exec -i -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" "$SANDBOX_NAME" bash -c \
            "cd '$SCRIPT_DIR' && claude --dangerously-skip-permissions --print $MODEL_FLAG" 2>&1 | tee /dev/stderr) || true
      fi
    fi
  else
    # Original direct execution (no sandbox)
    if [[ "$TOOL" == "amp" ]]; then
      if [ -f "$PROJECT_CLAUDE" ]; then
        OUTPUT=$(cat "$PROJECT_CLAUDE" "$prompt_file" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
      else
        OUTPUT=$(cat "$prompt_file" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
      fi
    elif [[ "$TOOL" == "codex" ]]; then
      # Codex: use --dangerously-bypass-approvals-and-sandbox for autonomous operation
      if [ -f "$PROJECT_CODEX" ]; then
        echo "Using project CODEX.md for context"
        OUTPUT=$(cat "$PROJECT_CODEX" "$prompt_file" | codex exec --dangerously-bypass-approvals-and-sandbox 2>&1 | tee /dev/stderr) || true
      else
        OUTPUT=$(cat "$prompt_file" | codex exec --dangerously-bypass-approvals-and-sandbox 2>&1 | tee /dev/stderr) || true
      fi
    else
      # Claude Code: use --dangerously-skip-permissions for autonomous operation, --print for output
      # Build model flag if specified
      MODEL_FLAG=""
      if [[ -n "$CLAUDE_MODEL" ]]; then
        MODEL_FLAG="--model $CLAUDE_MODEL"
      fi
      if [ -f "$PROJECT_CLAUDE" ]; then
        echo "Using project CLAUDE.md for context"
        OUTPUT=$(cat "$PROJECT_CLAUDE" "$prompt_file" | claude --dangerously-skip-permissions --print $MODEL_FLAG 2>&1 | tee /dev/stderr) || true
      else
        OUTPUT=$(cat "$prompt_file" | claude --dangerously-skip-permissions --print $MODEL_FLAG 2>&1 | tee /dev/stderr) || true
      fi
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
if [[ -n "$CLAUDE_MODEL" ]]; then
echo "  Model: $CLAUDE_MODEL"
fi
echo "  Docker Sandbox: $(if [[ "$USE_DOCKER_SANDBOX" == "true" ]]; then echo "Enabled"; else echo "Disabled"; fi)"
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

  # Show phase requirements for current feature
  # Note: Can't use "// true" as jq treats false as falsy and replaces it
  REQ_BACKEND=$(jq -r ".features[\"$CURRENT_FEATURE\"].requiresBackend" "$FEATURE_PROGRESS_FILE")
  REQ_FRONTEND=$(jq -r ".features[\"$CURRENT_FEATURE\"].requiresFrontend" "$FEATURE_PROGRESS_FILE")
  [[ "$REQ_BACKEND" == "null" ]] && REQ_BACKEND="true"
  [[ "$REQ_FRONTEND" == "null" ]] && REQ_FRONTEND="true"
  echo "Phases: Backend=$REQ_BACKEND, Frontend=$REQ_FRONTEND"

  # Check if feature is fully complete (QA passed)
  if [[ "$CURRENT_STATE" == "qa_passed" ]]; then
    echo ""
    echo "Feature $CURRENT_FEATURE fully complete!"
    echo "All required phases passed. Feature is ready for deployment."

    # Update prd.json to mark feature as complete
    echo "Updating prd.json: Setting $CURRENT_FEATURE passes=true"
    jq ".userStories |= map(if .id == \"$CURRENT_FEATURE\" then .passes = true else . end)" "$PRD_FILE" > "$PRD_FILE.tmp"
    mv "$PRD_FILE.tmp" "$PRD_FILE"

    # Clean up Docker sandbox for completed feature
    if [[ "$USE_DOCKER_SANDBOX" == "true" ]]; then
      SANDBOX_NAME=$(jq -r ".features[\"$CURRENT_FEATURE\"].sandboxName // \"null\"" "$FEATURE_PROGRESS_FILE")
      if [[ "$SANDBOX_NAME" != "null" ]] && [[ -n "$SANDBOX_NAME" ]]; then
        remove_sandbox "$SANDBOX_NAME"

        # Clear sandbox name from feature_progress.json
        jq ".features[\"$CURRENT_FEATURE\"].sandboxName = null" \
          "$FEATURE_PROGRESS_FILE" > "$FEATURE_PROGRESS_FILE.tmp"
        mv "$FEATURE_PROGRESS_FILE.tmp" "$FEATURE_PROGRESS_FILE"
      fi
    fi

    # Commit feature completion state
    echo "Committing feature completion for $CURRENT_FEATURE..."
    git add "$FEATURE_PROGRESS_FILE" "$PRD_FILE" 2>/dev/null || true
    git commit -m "Update $CURRENT_FEATURE status to passed" 2>/dev/null || echo "Nothing to commit"

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

      # Determine initial state based on feature requirements
      # Note: Can't use "// true" as jq treats false as falsy
      NEXT_REQUIRES_BACKEND=$(jq -r ".features[\"$NEXT_FEATURE\"].requiresBackend" "$FEATURE_PROGRESS_FILE")
      NEXT_REQUIRES_FRONTEND=$(jq -r ".features[\"$NEXT_FEATURE\"].requiresFrontend" "$FEATURE_PROGRESS_FILE")
      [[ "$NEXT_REQUIRES_BACKEND" == "null" ]] && NEXT_REQUIRES_BACKEND="true"
      [[ "$NEXT_REQUIRES_FRONTEND" == "null" ]] && NEXT_REQUIRES_FRONTEND="true"

      if [[ "$NEXT_REQUIRES_BACKEND" != "false" ]]; then
        INITIAL_STATE="backend_dev"
      else
        INITIAL_STATE="frontend_dev"
      fi

      echo "  Requires backend: $NEXT_REQUIRES_BACKEND"
      echo "  Requires frontend: $NEXT_REQUIRES_FRONTEND"
      echo "  Starting at: $INITIAL_STATE"

      # Update currentFeature and set initial state
      jq ".currentFeature = \"$NEXT_FEATURE\" | .features[\"$NEXT_FEATURE\"].state = \"$INITIAL_STATE\"" "$FEATURE_PROGRESS_FILE" > "$FEATURE_PROGRESS_FILE.tmp"
      mv "$FEATURE_PROGRESS_FILE.tmp" "$FEATURE_PROGRESS_FILE"
      sleep 2
      continue
    else
      echo ""
      echo "All features complete!"

      # Final commit of tracking files
      echo "Committing final state..."
      if git diff --quiet "$FEATURE_PROGRESS_FILE" "$PRD_FILE" 2>/dev/null; then
        echo "No uncommitted changes to tracking files."
      else
        git add "$FEATURE_PROGRESS_FILE" "$PRD_FILE" 2>/dev/null || true
        git commit -m "Update tracking files - all features complete" 2>/dev/null || echo "Nothing to commit or commit failed"
      fi

      exit 0
    fi
  fi

  # Handle auto-transition from backend to frontend (or QA if no frontend needed)
  if [[ "$CURRENT_STATE" == "backend_review_passed" ]]; then
    echo ""
    echo "Backend phase complete!"

    # Check if frontend is required for this feature
    if requires_frontend; then
      echo "Auto-transitioning to frontend development."
      jq ".features[\"$CURRENT_FEATURE\"].state = \"frontend_dev\"" "$FEATURE_PROGRESS_FILE" > "$FEATURE_PROGRESS_FILE.tmp"
      mv "$FEATURE_PROGRESS_FILE.tmp" "$FEATURE_PROGRESS_FILE"
      echo "State updated to: frontend_dev"
    else
      echo "No frontend required. Auto-transitioning to QA testing."
      jq ".features[\"$CURRENT_FEATURE\"].state = \"qa_testing\"" "$FEATURE_PROGRESS_FILE" > "$FEATURE_PROGRESS_FILE.tmp"
      mv "$FEATURE_PROGRESS_FILE.tmp" "$FEATURE_PROGRESS_FILE"
      echo "State updated to: qa_testing"
    fi
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
