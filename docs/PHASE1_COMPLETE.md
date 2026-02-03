# Phase 1 Complete: Minimal Viable Backend Loop

## What We Built

### 1. File Structures
- **`feature_progress.json.example`** - Schema for tracking feature state through the pipeline
- **`feature_progress.json`** (in test-project) - Actual tracking file initialized for US-001

### 2. Agent Prompts
- **`BACKEND_DEV.md`** - Detailed instructions for the Backend Developer agent
  - Implements features based on acceptance criteria
  - Handles review feedback and fixes issues
  - Updates tracking files and commits work
  - Outputs `BACKEND_DEV_COMPLETE` or `BACKEND_NO_WORK`

- **`BACKEND_REVIEWER.md`** - Detailed instructions for the Backend Reviewer agent
  - Reviews code for security, quality, correctness
  - Provides specific, actionable feedback
  - Handles max review cycles (configurable, default 5)
  - Approves if functionally correct after max cycles
  - Outputs `BACKEND_REVIEW_PASSED` or `BACKEND_REVIEW_FAILED`

### 3. Orchestrator Script
- **`ralph-extended.sh`** - Extended orchestrator that:
  - Reads `feature_progress.json` to determine current state
  - Spawns the appropriate agent (fresh Claude instance) based on state
  - Handles state transitions:
    - `backend_dev` → `backend_review`
    - `backend_review` → `backend_review_passed` (approved)
    - `backend_review` → `backend_review_failed` (rejected)
    - `backend_review_failed` → `backend_dev` (fix issues)
  - Tracks review cycle count
  - Continues until `backend_review_passed`
  - Supports both Amp and Claude Code (default: claude)

### 4. Test Project
- **`test-project/`** - Simple Go HTTP service for testing
  - Basic server structure in `cmd/server/main.go`
  - PRD with feature US-001: "Add /health endpoint"
  - Initialized `feature_progress.json` in `backend_dev` state
  - Git repository initialized with initial commit

---

## Architecture

### State Machine (Backend Loop Only)

```
backend_dev
    ↓ (BACKEND_DEV_COMPLETE or BACKEND_NO_WORK)
backend_review
    ↓ (BACKEND_REVIEW_PASSED)
backend_review_passed → EXIT (success)
    ↓ (BACKEND_REVIEW_FAILED)
backend_review_failed
    ↓ (increments reviewCycleCount)
backend_dev (fix issues)
    ... loop continues ...
```

### Fresh Context Per State

**Critical design decision**: Each state transition spawns a **fresh Claude Code instance**.

- `backend_dev` state → Spawns new Claude with `BACKEND_DEV.md` prompt
- `backend_review` state → Spawns new Claude with `BACKEND_REVIEWER.md` prompt
- Each instance is completely independent
- Memory persists ONLY through:
  - Git commits (code changes)
  - `feature_progress.json` (state and history)
  - `progress.txt` (learnings and context)
  - `prd.json` (feature requirements)

### Review Cycle Handling

Configurable in `feature_progress.json`:
```json
"config": {
  "maxReviewCycles": 5,
  "skipReviewAfterMax": true
}
```

After 5 review cycles:
- If code is **functionally correct** (tests pass, meets acceptance criteria): APPROVE
- If code has **functional bugs**: REJECT (safety takes priority)

---

## How to Test

### Prerequisites
1. Claude Code installed and authenticated
2. Go 1.21+ installed
3. `jq` installed (for JSON parsing in bash script)
4. `golangci-lint` installed (optional, for linting)

### Running the Test

```bash
# Navigate to test project
cd test-project/

# Run the extended Ralph system
../ralph-extended.sh --tool claude 20

# This will:
# 1. Read feature_progress.json (current state: backend_dev)
# 2. Spawn Backend Developer agent (fresh Claude instance)
# 3. Agent implements /health endpoint with tests
# 4. Agent commits work and updates feature_progress.json
# 5. Spawn Backend Reviewer agent (fresh Claude instance)
# 6. Reviewer checks code, tests, security
# 7. Either approves (exit) or rejects (loop back to dev)
# 8. Continue until backend_review_passed or max iterations
```

### Expected Outcome

**Success scenario**:
1. Backend Dev implements `/health` endpoint
2. Backend Dev writes tests
3. Backend Dev commits work
4. Backend Reviewer approves
5. Script exits with "Backend development complete!"

**Review failure scenario**:
1. Backend Dev implements feature (maybe with issues)
2. Backend Reviewer finds issues
3. Backend Dev receives feedback, fixes issues
4. Backend Reviewer re-reviews
5. Loop continues until approved or max cycles

### Monitoring Progress

While running, check:
```bash
# Current state
cat feature_progress.json | jq '.features[.currentFeature].state'

# Review cycle count
cat feature_progress.json | jq '.features[.currentFeature].reviewCycleCount'

# Full history
cat feature_progress.json | jq '.features[.currentFeature].history'

# Learnings
cat progress.txt
```

---

## Key Features Implemented

✅ **Fresh Claude instances per state** - No context bleeding
✅ **Configurable max review cycles** - Prevents infinite loops
✅ **File-based state persistence** - Git + JSON tracking
✅ **Detailed agent instructions** - Comprehensive prompts
✅ **Review feedback loop** - Backend Dev ↔ Backend Reviewer
✅ **"No work" handling** - Skip review if no backend changes
✅ **Safety after max cycles** - Approve only if functionally correct

---

## What's Next (Phase 2)

After validating Phase 1 works:

1. Add frontend states to `feature_progress.json`:
   - `frontend_dev`
   - `frontend_review`
   - `frontend_review_failed`
   - `frontend_review_passed`

2. Create agent prompts:
   - `FRONTEND_DEV.md`
   - `FRONTEND_REVIEWER.md`

3. Extend `ralph-extended.sh` to handle frontend loop

4. Test with a full-stack feature (backend + frontend)

---

## Files Modified/Created

### New Files
- `feature_progress.json.example` - Schema example
- `BACKEND_DEV.md` - Backend developer agent prompt
- `BACKEND_REVIEWER.md` - Backend reviewer agent prompt
- `ralph-extended.sh` - Extended orchestrator script
- `test-project/` - Test Go HTTP service
- `PHASE1_COMPLETE.md` - This file

### Existing Files (Unchanged)
- `ralph.sh` - Original Ralph (still works)
- `CLAUDE.md` - Original single-agent prompt
- `prd.json.example` - Original format
- All skills and flowchart files

---

## Testing Checklist

Before moving to Phase 2, validate:

- [ ] Backend Dev agent can implement the /health endpoint
- [ ] Backend Dev agent writes tests
- [ ] Backend Dev agent commits work
- [ ] Backend Dev agent updates feature_progress.json correctly
- [ ] Backend Reviewer agent can approve good code
- [ ] Backend Reviewer agent can reject code with issues
- [ ] Backend Reviewer agent provides specific, actionable feedback
- [ ] Review loop works (Dev fixes issues, Reviewer re-reviews)
- [ ] Max review cycles works (approves after 5 cycles if functionally correct)
- [ ] State transitions work correctly
- [ ] Fresh Claude instances maintain no memory between states
- [ ] Git history shows proper commits from agents

---

## Configuration

### feature_progress.json

```json
{
  "currentFeature": "US-001",
  "features": {
    "US-001": {
      "state": "backend_dev",           // Current state
      "reviewCycleCount": 0,            // Tracks review loops
      "history": [],                    // Agent actions log
      "currentIssues": []               // Issues from last review
    }
  },
  "config": {
    "maxReviewCycles": 5,               // Max review attempts
    "skipReviewAfterMax": true          // Approve if functional after max
  }
}
```

### ralph-extended.sh Options

```bash
# Use Claude Code (default)
./ralph-extended.sh

# Use Amp
./ralph-extended.sh --tool amp

# Set max iterations
./ralph-extended.sh --tool claude 30

# Both
./ralph-extended.sh --tool claude 50
```

Default: `--tool claude`, max iterations 20
