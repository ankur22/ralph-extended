# Ralph

![Ralph](ralph.webp)

Ralph is an autonomous AI agent loop that runs AI coding tools ([Amp](https://ampcode.com) or [Claude Code](https://docs.anthropic.com/en/docs/claude-code)) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context. Memory persists via git history, `progress.txt`, and `prd.json`.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

[Read my in-depth article on how I use Ralph](https://x.com/ryancarson/status/2008548371712135632)

## Prerequisites

- One of the following AI coding tools installed and authenticated:
  - [Amp CLI](https://ampcode.com) (default)
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
  - [OpenAI Codex CLI](https://github.com/openai/codex) (`npm install -g @openai/codex`)
- `jq` installed (`brew install jq` on macOS)
- A git repository for your project

## Setup

### Option 1: Copy to your project

Copy the ralph files into your project:

```bash
# From your project root
mkdir -p scripts/ralph
cp /path/to/ralph/ralph.sh scripts/ralph/

# Copy the prompt template for your AI tool of choice:
cp /path/to/ralph/prompt.md scripts/ralph/prompt.md    # For Amp
# OR
cp /path/to/ralph/CLAUDE.md scripts/ralph/CLAUDE.md    # For Claude Code

chmod +x scripts/ralph/ralph.sh
```

### Option 2: Install skills globally (Amp)

Copy the skills to your Amp or Claude config for use across all projects:

For AMP
```bash
cp -r skills/prd ~/.config/amp/skills/
cp -r skills/ralph ~/.config/amp/skills/
```

For Claude Code (manual)
```bash
cp -r skills/prd ~/.claude/skills/
cp -r skills/ralph ~/.claude/skills/
```

### Option 3: Use as Claude Code Marketplace

Add the Ralph marketplace to Claude Code:

```bash
/plugin marketplace add snarktank/ralph
```

Then install the skills:

```bash
/plugin install ralph-skills@ralph-marketplace
```

Available skills after installation:
- `/prd` - Generate Product Requirements Documents
- `/ralph` - Convert PRDs to prd.json format

Skills are automatically invoked when you ask Claude to:
- "create a prd", "write prd for", "plan this feature"
- "convert this prd", "turn into ralph format", "create prd.json"

### Configure Amp auto-handoff (recommended)

Add to `~/.config/amp/settings.json`:

```json
{
  "amp.experimental.autoHandoff": { "context": 90 }
}
```

This enables automatic handoff when context fills up, allowing Ralph to handle large stories that exceed a single context window.

## Ralph Extended - Multi-Agent System

Ralph Extended is an advanced version that uses **5 specialized agents** (Backend Dev, Backend Reviewer, Frontend Dev, Frontend Reviewer, QA) working sequentially. Each agent is a fresh Claude Code instance with a specific role.

See [AGENTS.md](./AGENTS.md) for complete documentation and [docs/AI-Extended-Ralph-Agent-Flow.md](./docs/AI-Extended-Ralph-Agent-Flow.md) for design rationale.

### Setup for Ralph Extended

#### Prerequisites

Before running Ralph Extended:

1. **Docker Desktop 4.50+** with Docker AI Sandboxes feature enabled
   - Install from [docker.com](https://www.docker.com/products/docker-desktop/)
   - Verify: `docker sandbox --help` should show sandbox commands

2. **AI Tool CLI** installed globally (one of the following):
   - **Claude Code**: `npm install -g @anthropic-ai/claude-code`
   - **OpenAI Codex**: `npm install -g @openai/codex`

3. **Authentication** configured for your chosen tool:

   **For Claude Code** - Anthropic API Key exported as environment variable
   - Docker sandboxes cannot access the host's keychain
   - **Recommended**: Export directly from macOS keychain:
     ```bash
     export ANTHROPIC_API_KEY=$(security find-generic-password -s "Claude Code" -a "$USER" -w)
     ```
   - **Alternative**: Get your key from [console.anthropic.com](https://console.anthropic.com/) and export manually:
     ```bash
     export ANTHROPIC_API_KEY='your-api-key-here'
     ```

   **For OpenAI Codex** - Browser-based authentication cached locally
   - Run `codex login` on your host machine first
   - This creates `~/.codex/auth.json` which is copied into Docker sandboxes automatically
   - No environment variable needed

4. **jq** for JSON processing
   - macOS: `brew install jq`
   - Linux: `apt-get install jq`

5. **Git** repository initialized in your project

#### Installation

Copy the ralph-extended files into your project:

```bash
# From your project root
mkdir -p scripts/ralph
cp /path/to/ralph-extended/ralph-extended.sh scripts/ralph/
cp -r /path/to/ralph-extended/agents scripts/ralph/

chmod +x scripts/ralph/ralph-extended.sh
```

**Note:** Do NOT copy `prompt.md` or `CLAUDE.md` - Ralph Extended agents use their own instructions from the `agents/` directory.

### Running Ralph Extended

```bash
# Using Claude Code with Docker Sandbox (recommended)
./scripts/ralph/ralph-extended.sh --tool claude [max_iterations]

# Specify a Claude model (e.g., Opus 4.5 for complex tasks)
./scripts/ralph/ralph-extended.sh --tool claude --model claude-opus-4-20250514 [max_iterations]

# Using OpenAI Codex with Docker Sandbox
./scripts/ralph/ralph-extended.sh --tool codex [max_iterations]

# Disable sandbox isolation (legacy mode)
./scripts/ralph/ralph-extended.sh --tool claude --no-sandbox [max_iterations]

# Using Amp with Docker Sandbox
./scripts/ralph/ralph-extended.sh --tool amp [max_iterations]
```

**Available options:**
- `--tool`: AI tool to use (`claude`, `codex`, or `amp`, default: `claude`)
- `--model`: Claude model to use (e.g., `claude-sonnet-4-20250514`, `claude-opus-4-20250514`)
- `--no-sandbox`: Disable Docker sandbox isolation (runs agents on host)
- `--sandbox`: Enable Docker sandbox isolation (default)

Default is 20 iterations. Ralph Extended will:
1. Create `feature_progress.json` from your `prd.json` (automatically on first run)
2. Create a Docker sandbox for each feature (isolated execution environment)
3. Route each feature through the agent pipeline:
   - Backend Dev → Backend Review → Frontend Dev → Frontend Review → QA
4. Route issues back to the appropriate dev agent based on failure type
5. Track state and history in `feature_progress.json`
6. Update `progress.txt` with learnings from each agent
7. Clean up sandbox when feature completes

**Docker Sandbox Mode (Default):**
- Agents run inside isolated Docker containers
- Each feature gets its own sandbox
- Sandbox persists across agents within the same feature
- Automatic cleanup when feature completes
- Use `--no-sandbox` to disable and run agents on host system

### Key Differences: Ralph vs Ralph Extended

| Aspect | Ralph | Ralph Extended |
|--------|-------|----------------|
| **Agent Model** | Single general-purpose agent | 5 specialized agents (Backend Dev, Backend Review, Frontend Dev, Frontend Review, QA) |
| **Workflow** | Single agent does all work | Sequential pipeline with blocking reviews |
| **Review Process** | Tests only | Dedicated code review agents before QA |
| **QA Process** | Tests only | Dedicated QA agent with k6 (functional + e2e tests) |
| **Issue Routing** | Agent fixes own issues | Targeted routing to backend/frontend dev based on failure type |
| **State Tracking** | `prd.json` only | `prd.json` + `feature_progress.json` (detailed history) |
| **Test Framework** | Any | k6 for API tests and browser automation |

### Ralph Extended Files

| File | Purpose |
|------|---------|
| `ralph-extended.sh` | Bash orchestrator that spawns specialized agents |
| `agents/BACKEND_DEV.md` | Backend developer agent instructions |
| `agents/BACKEND_REVIEWER.md` | Backend code reviewer agent instructions |
| `agents/FRONTEND_DEV.md` | Frontend developer agent instructions |
| `agents/FRONTEND_REVIEWER.md` | Frontend code reviewer agent instructions |
| `agents/QA.md` | QA engineer agent instructions (k6 testing) |
| `feature_progress.json` | Detailed state tracking for each feature |
| `tests.json` | k6 test suite configuration |
| `examples/` | Example files for reference |
| `docs/` | Complete documentation and design docs |

## Workflow

### 1. Create a PRD

Use the PRD skill to generate a detailed requirements document:

```
Load the prd skill and create a PRD for [your feature description]
```

Answer the clarifying questions. The skill saves output to `tasks/prd-[feature-name].md`.

### 2. Convert PRD to Ralph format

Use the Ralph skill to convert the markdown PRD to JSON:

```
Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json
```

This creates `prd.json` with user stories structured for autonomous execution.

### 3. Run Ralph

```bash
# Using Amp (default)
./scripts/ralph/ralph.sh [max_iterations]

# Using Claude Code
./scripts/ralph/ralph.sh --tool claude [max_iterations]
```

Default is 10 iterations. Use `--tool amp` or `--tool claude` to select your AI coding tool.

Ralph will:
1. Create a feature branch (from PRD `branchName`)
2. Pick the highest priority story where `passes: false`
3. Implement that single story
4. Run quality checks (typecheck, tests)
5. Commit if checks pass
6. Update `prd.json` to mark story as `passes: true`
7. Append learnings to `progress.txt`
8. Repeat until all stories pass or max iterations reached

## Key Files

| File | Purpose |
|------|---------|
| `ralph.sh` | The bash loop that spawns fresh AI instances (supports `--tool amp` or `--tool claude`) |
| `prompt.md` | Prompt template for Amp |
| `CLAUDE.md` | Prompt template for Claude Code |
| `prd.json` | User stories with `passes` status (the task list) |
| `prd.json.example` | Example PRD format for reference |
| `progress.txt` | Append-only learnings for future iterations |
| `skills/prd/` | Skill for generating PRDs (works with Amp and Claude Code) |
| `skills/ralph/` | Skill for converting PRDs to JSON (works with Amp and Claude Code) |
| `.claude-plugin/` | Plugin manifest for Claude Code marketplace discovery |
| `flowchart/` | Interactive visualization of how Ralph works |

## Flowchart

[![Ralph Flowchart](ralph-flowchart.png)](https://snarktank.github.io/ralph/)

**[View Interactive Flowchart](https://snarktank.github.io/ralph/)** - Click through to see each step with animations.

The `flowchart/` directory contains the source code. To run locally:

```bash
cd flowchart
npm install
npm run dev
```

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new AI instance** (Amp or Claude Code) with clean context. The only memory between iterations is:
- Git history (commits from previous iterations)
- `progress.txt` (learnings and context)
- `prd.json` (which stories are done)

### Small Tasks

Each PRD item should be small enough to complete in one context window. If a task is too big, the LLM runs out of context before finishing and produces poor code.

Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

Too big (split these):
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

### AGENTS.md Updates Are Critical

After each iteration, Ralph updates the relevant `AGENTS.md` files with learnings. This is key because AI coding tools automatically read these files, so future iterations (and future human developers) benefit from discovered patterns, gotchas, and conventions.

Examples of what to add to AGENTS.md:
- Patterns discovered ("this codebase uses X for Y")
- Gotchas ("do not forget to update Z when changing W")
- Useful context ("the settings panel is in component X")

### Feedback Loops

Ralph only works if there are feedback loops:
- Typecheck catches type errors
- Tests verify behavior
- CI must stay green (broken code compounds across iterations)

### Browser Verification for UI Stories

Frontend stories must include "Verify in browser using dev-browser skill" in acceptance criteria. Ralph will use the dev-browser skill to navigate to the page, interact with the UI, and confirm changes work.

### Stop Condition

When all stories have `passes: true`, Ralph outputs `<promise>COMPLETE</promise>` and the loop exits.

## Debugging

Check current state:

```bash
# See which stories are done
cat prd.json | jq '.userStories[] | {id, title, passes}'

# See learnings from previous iterations
cat progress.txt

# Check git history
git log --oneline -10
```

## Customizing the Prompt

After copying `prompt.md` (for Amp) or `CLAUDE.md` (for Claude Code) to your project, customize it for your project:
- Add project-specific quality check commands
- Include codebase conventions
- Add common gotchas for your stack

## Archiving

Ralph automatically archives previous runs when you start a new feature (different `branchName`). Archives are saved to `archive/YYYY-MM-DD-feature-name/`.

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Amp documentation](https://ampcode.com/manual)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
