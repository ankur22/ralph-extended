# Ralph Extended - Multi-Agent Autonomous Coding System

## Overview

Ralph Extended is an autonomous multi-agent system that orchestrates specialized AI agents to implement, review, and test software features end-to-end. Each agent is a fresh Claude Code instance with a specific role, working together through a bash orchestrator.

**Design Document:** See [AI-Extended-Ralph-Agent-Flow.md](./docs/AI-Extended-Ralph-Agent-Flow.md) for the complete design rationale, open questions, and future directions that guided this implementation.

## Architecture

### Multi-Agent System
The system uses **5 specialized agents** that work sequentially:

1. **Backend Developer** - Implements backend features (API, database, business logic)
2. **Backend Reviewer** - Reviews backend code for quality, security, and correctness
3. **Frontend Developer** - Implements UI features (components, pages, styling)
4. **Frontend Reviewer** - Reviews frontend code for accessibility, UX, and quality
5. **QA Engineer** - Tests features with k6 (functional API tests + e2e browser tests)

### Orchestrator Flow

```
┌─────────────┐
│   Start     │
│  Feature    │
└──────┬──────┘
       │
       v
┌─────────────────────────────────────────────────────┐
│ Backend Phase                                        │
│  Backend Dev → Backend Review ⟲ (if failed)        │
└──────────────────────┬──────────────────────────────┘
                       │ (auto-transition)
                       v
┌─────────────────────────────────────────────────────┐
│ Frontend Phase                                       │
│  Frontend Dev → Frontend Review ⟲ (if failed)      │
└──────────────────────┬──────────────────────────────┘
                       │ (auto-transition)
                       v
┌─────────────────────────────────────────────────────┐
│ QA Phase                                             │
│  QA Testing → Route issues by layer                 │
│    ↓ backend issues    ↓ frontend issues            │
│  Backend Dev         Frontend Dev                   │
│    ↓                   ↓                             │
│  Backend Review      Frontend Review                │
│    ↓                   ↓                             │
│  QA Testing (retest) ←┘                             │
└──────────────────────┬──────────────────────────────┘
                       │ (all tests pass)
                       v
                  ┌─────────┐
                  │Complete │
                  └─────────┘
```

## Commands

```bash
# Run Ralph Extended with Claude Code (recommended)
./ralph-extended.sh --tool claude [max_iterations]

# Run Ralph Extended with Amp
./ralph-extended.sh --tool amp [max_iterations]

# Default max_iterations: 20
./ralph-extended.sh --tool claude
```

## Key Files

### Agent Prompts
- `BACKEND_DEV.md` - Backend developer agent instructions
- `BACKEND_REVIEWER.md` - Backend reviewer agent instructions
- `FRONTEND_DEV.md` - Frontend developer agent instructions
- `FRONTEND_REVIEWER.md` - Frontend reviewer agent instructions
- `QA.md` - QA engineer agent instructions

### Orchestrator & Configuration
- `ralph-extended.sh` - Bash orchestrator that spawns agents and manages state transitions
- `prd.json` - Product requirements (user stories with acceptance criteria)
- `feature_progress.json` - Tracks current state, history, and issues for each feature
- `progress.txt` - Append-only log of all agent work and learnings
- `tests.json` - k6 test suite configuration for QA testing

### Examples & Documentation
- `examples/feature_progress.json.example` - Example tracking structure with QA history
- `examples/tests.json.example` - Example test configuration with functional and e2e tests
- `docs/PHASE1_COMPLETE.md` - Backend phase documentation
- `docs/PHASE2_COMPLETE.md` - Frontend phase documentation
- `docs/PHASE3_COMPLETE.md` - QA phase documentation (complete system overview)

### Test Templates
- `test-project/tests/k6/template-functional.js` - API testing template
- `test-project/tests/k6/template-e2e.js` - Browser testing template
- `test-project/tests/k6/README.md` - k6 testing guide

## Getting Started

### 1. Create a PRD
Create `prd.json` with your user stories:

```json
{
  "userStories": [
    {
      "id": "US-001",
      "title": "Health Check Endpoint",
      "description": "Add /health endpoint for monitoring",
      "acceptanceCriteria": [
        "GET /health returns 200 OK",
        "Response includes status field",
        "Response includes timestamp"
      ],
      "passes": false
    }
  ]
}
```

### 2. Run the Orchestrator
The orchestrator will automatically create `feature_progress.json` from your PRD:

```bash
./ralph-extended.sh --tool claude 20
```

### 3. Monitor Progress
Watch as agents:
- Implement features
- Review each other's work
- Fix issues through iteration
- Test with k6
- Route issues back to the right agent

## State Management

### Feature States
Each feature progresses through these states:

- `pending` - Not started yet
- `backend_dev` - Backend developer working
- `backend_review` - Backend reviewer evaluating
- `backend_review_passed` - Backend approved, auto-transition to frontend
- `frontend_dev` - Frontend developer working
- `frontend_review` - Frontend reviewer evaluating
- `frontend_review_passed` - Frontend approved, auto-transition to QA
- `qa_testing` - QA engineer testing
- `qa_passed` - All tests passed, feature complete

### Issue Routing States
When QA finds issues, features route to:

- `qa_issues_backend` - Routes to backend_dev with specific issues
- `qa_issues_frontend` - Routes to frontend_dev with specific issues

After fixes, the feature returns to `qa_testing` for retesting.

## Key Patterns

### Docker Sandbox Isolation

Ralph Extended uses Docker AI Sandboxes to isolate agent execution:

- **Sandbox lifecycle**: Created when feature starts, removed when feature completes
- **Persistence within feature**: Same sandbox reused for all agents in a feature (Backend Dev → Review → Frontend Dev → Review → QA)
- **Isolation between features**: Each feature gets a fresh sandbox
- **File synchronization**: Project directory mounted as volume - agents can read/write files
- **Git operations**: Full git access within sandbox boundary
- **Dependencies**: Claude Code, jq, git installed automatically on sandbox creation

**Requirements:**
- Docker Desktop 4.50+ installed and running
- `docker sandbox` command available
- Sufficient Docker resources (memory/CPU for container)

**Disabling sandbox mode:**
Use `--no-sandbox` flag to run agents directly on the host system (legacy mode).

### Model Selection

Use the `--model` flag to specify which Claude model all agents use:

```bash
# Use Opus 4.5 for complex reasoning tasks
./ralph-extended.sh --model claude-opus-4-20250514

# Use Sonnet 4 (faster, cost-effective)
./ralph-extended.sh --model claude-sonnet-4-20250514
```

**Model recommendations:**
- **Opus 4.5**: Best for complex architectural decisions, nuanced code review, and difficult debugging
- **Sonnet 4**: Good balance of speed and capability for most development tasks
- **Default**: If not specified, uses Claude Code's default model

### Fresh Instances
- Each agent spawns as a fresh Claude Code instance
- No context carries over between agents
- Memory persists via git commits and tracking files

### File-Based Persistence
- `feature_progress.json` - Current state, history, issues, sandbox name
- `progress.txt` - Append-only learning log
- `tests.json` - Test configurations
- Git history - Full audit trail

### Output Markers
Agents output specific markers for the orchestrator to detect completion:

- `BACKEND_DEV_COMPLETE` / `BACKEND_NO_WORK`
- `BACKEND_REVIEW_PASSED` / `BACKEND_REVIEW_FAILED`
- `FRONTEND_DEV_COMPLETE` / `FRONTEND_NO_WORK`
- `FRONTEND_REVIEW_PASSED` / `FRONTEND_REVIEW_FAILED`
- `QA_TESTING_COMPLETE` / `QA_NO_TESTING` / `QA_ISSUES_BACKEND` / `QA_ISSUES_FRONTEND`

### Auto-Transitions
The orchestrator automatically transitions between phases:
- `backend_review_passed` → `frontend_dev`
- `frontend_review_passed` → `qa_testing`
- `qa_passed` → mark complete, start next feature

### Review Cycles
- Maximum cycles per phase (default: 5)
- Tracks `reviewCycleCount` in feature_progress.json
- After max cycles, can approve with warnings if feature is functionally correct

## QA Testing

### Functional Tests (k6 HTTP)
Test API endpoints:
- Status codes (200, 400, 404, 500)
- Response schemas
- Performance thresholds (p95 < 500ms)
- Error handling
- Edge cases

Example:
```bash
k6 run tests/k6/us-001-functional.js
```

### E2E Tests (k6 Browser)
Test UI and user flows:
- Element visibility and interactions
- Form validation
- Loading and error states
- Accessibility (ARIA labels, keyboard navigation)
- Visual formatting

Example:
```bash
k6 run tests/k6/us-001-e2e.js
```

### Issue Categorization
QA agent automatically categorizes failures:

**Backend issues:**
- API returns wrong status code
- Timeout or connection errors
- Response schema mismatch
- Performance issues

**Frontend issues:**
- Element not found/visible
- Rendering or layout issues
- JavaScript errors
- Accessibility violations

## Configuration

### feature_progress.json Config Section
```json
{
  "config": {
    "maxReviewCycles": 5,
    "skipReviewAfterMax": true,
    "maxQACycles": 5,
    "skipQAAfterMax": true
  }
}
```

### tests.json Config Section
```json
{
  "config": {
    "baseUrl": "http://localhost:8080",
    "timeout": 30000,
    "retries": 2,
    "parallelExecution": false,
    "maxQACycles": 5
  }
}
```

## Edge Cases Handled

### No Work Needed
If a feature doesn't require work in a phase (e.g., backend-only, no UI):
- Agent updates tracking with `hasWork: false`
- Auto-skips review (no work to review)
- Proceeds to next phase

### Max Cycles Reached
After maximum review/QA cycles:
- If feature is functionally correct with minor issues: Approve with warning
- If critical bugs remain: Continue cycling (safety override)

### Test Failures
QA routes issues by layer:
- Backend issues → Backend Dev
- Frontend issues → Frontend Dev
- Both present → Backend first (dependency order)

### Flaky Tests
- Uses `config.retries` (default: 2)
- Notes flakiness in progress.txt
- Recommends test improvements

## CLAUDE.md Project Instructions

The root `CLAUDE.md` file is included in every agent's context, providing:
- Project-specific patterns and conventions
- Codebase structure learnings
- Common gotchas to avoid
- Testing requirements

Agents can update `CLAUDE.md` files in subdirectories to document module-specific learnings.

## Progress Tracking

### progress.txt Format
```
## [Date/Time] - [Story ID] - [Agent Role]
- What was implemented
- Files changed: [list]
- Tests added/run: [results]
- **Learnings for future iterations:**
  - Patterns discovered
  - Gotchas encountered
  - Useful context
---
```

### Codebase Patterns Section
Top of progress.txt consolidates reusable learnings:
```
## Codebase Patterns
- Use `sql<number>` template for aggregations
- Always use `IF NOT EXISTS` for migrations
- Export types from actions.ts for UI components
```

## Advanced Features

### Custom Base URL for Tests
```bash
BASE_URL=http://localhost:3000 k6 run tests/k6/us-001-functional.js
```

### Parallel Execution
Set `parallelExecution: true` in tests.json config to run multiple test suites concurrently.

### Test Retries
Configure flaky test handling:
```json
{
  "config": {
    "retries": 2
  }
}
```

## Troubleshooting

### Agent Stuck/Not Completing
- Check if agent output contains completion marker (grep for `COMPLETE` or `PASSED` or `FAILED`)
- Kill hung processes: `ps aux | grep claude` then `kill <pid>`
- Check feature_progress.json for current state

### Tests Failing
- Ensure application is running locally
- Check test selectors match actual UI
- Verify API endpoints are accessible
- Review test logs for specific errors

### State Not Transitioning
- Verify agent updated feature_progress.json
- Check git commits for tracking file updates
- Look for error messages in orchestrator output

## Next Steps (Future Phases)

The following phases are planned to extend Ralph Extended's capabilities. See [AI-Extended-Ralph-Agent-Flow.md](./docs/AI-Extended-Ralph-Agent-Flow.md) for detailed open questions and design considerations.

### Phase 4: Docker Expertise Agent

Add containerization and deployment expertise:

**Capabilities:**
- Generate production-ready Dockerfiles and docker-compose.yml
- Optimize container images (multi-stage builds, layer caching)
- Configure health checks and resource limits
- Set up local development environments with Docker
- Generate CI/CD pipeline configurations (GitHub Actions, GitLab CI)

**Integration:**
- Runs after QA phase passes
- Creates containerization artifacts
- Tests container builds locally
- Validates health checks and startup

**Tools:**
- Docker, docker-compose
- Hadolint (Dockerfile linting)
- Dive (image layer analysis)
- Container security scanning (Trivy, Snyk)

### Phase 5: Observability Tooling Agent

Add monitoring, logging, and alerting:

**Capabilities:**
- Instrument code with metrics (Prometheus, StatsD)
- Add structured logging (zerolog, slog, winston)
- Configure distributed tracing (OpenTelemetry, Jaeger)
- Set up health check endpoints
- Create dashboards (Grafana, Datadog)
- Configure alerts for critical metrics

**Integration:**
- Runs parallel to Docker phase or after
- Adds instrumentation to existing code
- Updates tests to verify metrics/logs
- Generates observability documentation

**Tools:**
- Prometheus, Grafana
- OpenTelemetry
- Structured logging libraries
- APM tools (Datadog, New Relic)

### Phase 6: Adaptive Requirements (Open Question)

**Challenge:** Requirements evolve as edge cases are discovered during implementation.

**Potential Approaches:**
1. **Checkpoint Reviews** - After each feature, orchestrator reviews if remaining features still make sense
2. **Feedback Loops to PRD** - Allow agents to propose PRD amendments when they discover blockers
3. **MVP-First with "5 Whys"** - Use rigorous descoping at initialization to reduce mid-flight pivots
4. **Pivot Protocol** - Define formal process for requirement changes mid-project
5. **Feature Dependencies Graph** - Track dependencies so pivots cascade appropriately

**Research Needed:**
- How to detect when requirements need to change
- Authority model: Can agents auto-adjust or need user approval?
- Rollback strategy when pivots invalidate completed work
- Cost-benefit analysis of pivot vs completing original plan

### Phase 7: Competitive Implementation (Open Question)

**Challenge:** How do we know the implementation is the *best* one?

**Proposed Approach:**
- Multiple agents implement the same feature in parallel
- Panel of reviewers vote on the best implementation
- Winner proceeds to QA phase
- Losing implementations archived for learning

**Example Flow:**
```
Feature F-001:
1. Backend Dev Agent A → Implementation A
2. Backend Dev Agent B → Implementation B
3. Backend Dev Agent C → Implementation C
4. Review Panel votes → Winner: Implementation B
5. Implementation B → Normal flow (Review → QA → Fix cycle)
```

**Trade-offs:**
- **Pros:** Higher quality through competition, diverse approaches explored, reduces single-agent bias
- **Cons:** 2-3x more compute/tokens, more complex orchestration, slower overall throughput

**Open Questions:**
- How many competing implementations? (2 vs 3 vs more)
- How many reviewers? (3 minimum for tie-breaking)
- What if all implementations fail criteria?
- Should reviewers see each other's votes? (probably not, to avoid bias)
- How to handle losing code? (discard, archive for learning, merge good parts?)
- Only use competitive mode for complex/critical features?

### Phase 8: Security Testing Agent

Add dedicated security analysis:

**Capabilities:**
- Static analysis (Semgrep, Snyk, SonarQube)
- Dependency vulnerability scanning
- Dynamic security testing (OWASP ZAP)
- Secret detection in code and git history
- Security best practices validation (OWASP Top 10)
- Container vulnerability scanning (Trivy)

**Integration:**
- Runs parallel to QA phase or after
- Routes security issues back to appropriate dev agent
- Blocks deployment if critical vulnerabilities found

### Phase 9: Performance Testing Agent

Extend QA with load and stress testing:

**Capabilities:**
- Load testing with k6 (multiple VUs, sustained load)
- Stress testing (find breaking points)
- Spike testing (sudden traffic bursts)
- Soak testing (long-duration stability)
- Performance regression detection
- API response time monitoring

**Integration:**
- Runs after functional QA passes
- Uses k6 with higher VU counts and longer durations
- Compares metrics against baselines
- Routes performance issues to backend dev

### Phase 10: Documentation Agent

Auto-generate and maintain documentation:

**Capabilities:**
- API documentation (OpenAPI/Swagger from code)
- Generate CHANGELOG.md from commits
- Update README.md with new features
- Create architecture diagrams (mermaid, plantuml)
- Generate user guides from acceptance criteria
- Document deployment procedures

**Integration:**
- Runs after QA passes, before deployment
- Updates documentation in the same commit
- Validates documentation links and code examples

### Phase 11: Deployment Agent

Automated staging and production deployment:

**Capabilities:**
- Deploy to staging environment
- Run smoke tests on staging
- Deploy to production (with approval gate)
- Rollback on failure
- Blue-green or canary deployments
- Database migrations

**Integration:**
- Runs after all testing and documentation complete
- Requires manual approval for production deployment
- Monitors deployment health
- Auto-rollback on critical errors

## Troubleshooting

### Docker Sandbox Issues

**Sandbox creation fails:**
```bash
# Check Docker Desktop is running
docker ps

# Verify sandbox feature is available
docker sandbox --help
```

**Agent can't access files:**
- Ensure project directory is mounted correctly
- Check sandbox with: `docker sandbox exec -it <sandbox-name> ls -la`

**Dependencies missing in sandbox:**
- Reinstall: `docker sandbox exec <sandbox-name> npm install -g @anthropic-ai/claude-code`
- Check: `docker sandbox exec <sandbox-name> which claude`

**Sandbox not cleaned up:**
```bash
# List all sandboxes
docker sandbox ls

# Remove specific sandbox
docker sandbox rm ralph-extended-<feature-id>

# Remove all ralph sandboxes
docker sandbox ls | grep ralph-extended | awk '{print $1}' | xargs -I {} docker sandbox rm {}
```

**Git operations fail in sandbox:**
```bash
# Check git config in sandbox
docker sandbox exec <sandbox-name> git config --list

# Reconfigure git
docker sandbox exec <sandbox-name> bash -c "
  git config --global user.name 'Ralph Extended'
  git config --global user.email 'ralph@extended.local'
  git config --global --add safe.directory '*'
"
```

**API key errors ("Invalid API key"):**
Docker sandboxes cannot access the host's keychain. Export the API key before running:
```bash
# macOS - retrieve from keychain
export ANTHROPIC_API_KEY=$(security find-generic-password -s "Claude Code" -a "$USER" -w)

# Or set manually
export ANTHROPIC_API_KEY='your-api-key-here'
```

## Resources

- [k6 Documentation](https://k6.io/docs/)
- [k6 Browser Testing](https://k6.io/docs/using-k6-browser/)
- [Docker AI Sandboxes](https://docs.docker.com/ai/sandboxes/)
- [Docker Sandboxes + Claude Code](https://blog.arcade.dev/using-docker-sandboxes-with-claude-code)
- [Ralph Extended GitHub](https://github.com/anthropics/ralph-extended)

---

**Last Updated:** Phase 3 Complete - QA Agent with k6 Integration + Docker Sandbox Support
