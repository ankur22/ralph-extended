---
name: prd
description: "Generate a Product Requirements Document (PRD) for a new feature. Use when planning a feature, starting a new project, or when asked to create a PRD. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out."
user-invocable: true
---

# PRD Generator

Create detailed Product Requirements Documents that are clear, actionable, and suitable for implementation.

---

## The Job

1. Receive a feature description from the user
2. **Ask if they want research first** (recommended for complex or unfamiliar codebases)
3. If yes: Conduct research phase and save to `tasks/research-[feature-name].md`
4. Ask 3-5 essential clarifying questions (informed by research if conducted)
5. Generate a structured PRD based on answers
6. Save to `tasks/prd-[feature-name].md`

**Important:** Do NOT start implementing. Just create the PRD.

---

## Step 0: Research Decision

After receiving the feature request, ask the user:

```
Before creating the PRD, would you like me to research the codebase and external sources first?

This is recommended for:
- Complex features in large codebases
- Features in unfamiliar projects
- Features that may interact with existing systems

1. Would you like me to conduct research first?
   A. Yes, do thorough research (recommended for complex features)
   B. Yes, but keep it quick (for simpler features)
   C. No, I already know the codebase well enough
   D. No, let's just create the PRD directly

2. If researching, any specific areas I should focus on?
   A. Codebase only (no external research)
   B. External docs and GitHub issues only
   C. Both codebase and external sources (recommended)
   D. Other: [please specify]
```

If user chooses research (A or B for question 1), proceed to the Research Phase.
Otherwise, skip to Step 1: Clarifying Questions.

---

## Research Phase

When research is requested, follow these steps:

### Phase 1: Gather Initial Context

Automatically read project context files:
- `CLAUDE.md` / `AGENTS.md` (if they exist)
- `README.md`
- Any existing PRDs in `tasks/`
- `progress.txt` (for learnings from previous work)

### Phase 2: Get User Guidance

Ask the user:

```
To focus my research, please help me understand:

1. Where in the codebase should I start looking?
   (e.g., "src/components/", "internal/api/", "the auth module")

2. Are there existing features similar to this one I should study?
   (e.g., "look at how filtering works", "check the user settings page")

3. Any GitHub issues, docs, or external resources I should review?
   (e.g., "issue #123", "the official k6 docs on extensions")

4. What's the project's official documentation or community resources?
   (e.g., "https://docs.example.com", "their Discord", "Stack Overflow tag")
```

### Phase 3: Codebase Deep Dive

Using the guidance from Phase 2, conduct a thorough exploration:

1. **Search for related code patterns**
   - Find files matching the suggested areas
   - Look for similar existing features
   - Identify naming conventions and patterns

2. **Understand the architecture**
   - How is the codebase structured?
   - What patterns are used for similar features?
   - What testing approaches exist?

3. **Map dependencies**
   - What modules would this feature interact with?
   - Are there shared utilities or components to reuse?
   - What are the integration points?

4. **Review tests**
   - How are similar features tested?
   - What test patterns should be followed?

Use the Explore agent (Task tool with subagent_type=Explore) for thorough codebase investigation.

### Phase 4: External Research

If external research was requested, search for:

1. **Official Documentation**
   - Project docs relevant to the feature area
   - API references
   - Architecture guides

2. **GitHub Issues**
   - Related feature requests
   - Previous discussions about similar functionality
   - Known limitations or constraints

3. **Community Resources**
   - Forum discussions
   - Stack Overflow questions
   - Blog posts about the architecture

Use WebSearch and WebFetch tools for external research. Focus on the specific project's resources rather than broad searches.

### Phase 5: Save Research Findings

Save all findings to `tasks/research-[feature-name].md` with this structure:

```markdown
# Research: [Feature Name]

**Date:** [Date]
**Feature:** [Brief description]

## Executive Summary

[2-3 sentences summarizing key findings and recommendations]

## Codebase Analysis

### Relevant Files & Modules
- `path/to/file.ts` - [What it does, why it's relevant]
- `path/to/module/` - [Module purpose]

### Existing Patterns
- [Pattern 1]: [How it's used, where to find examples]
- [Pattern 2]: [Description]

### Reusable Components
- [Component/utility name]: [What it does, how to use it]

### Testing Approach
- [How similar features are tested]
- [Test file locations]

## External Research

### Official Documentation
- [Link]: [Key takeaways]

### GitHub Issues
- [#123](link): [Summary of discussion]
- [#456](link): [Relevant context]

### Community Insights
- [Source]: [Key insight]

## Technical Considerations

### Constraints
- [Constraint 1]
- [Constraint 2]

### Dependencies
- [What this feature depends on]
- [What might depend on this feature]

### Risks
- [Potential risk 1]
- [Potential risk 2]

## Recommendations

### Suggested Approach
[High-level recommendation for implementation]

### Files to Modify
- `path/to/file.ts` - [What changes needed]

### Files to Create
- `path/to/new/file.ts` - [Purpose]

## Open Questions

- [Question needing clarification]
- [Another question]
```

### Phase 6: Present Summary to User

After saving the research file, present a summary:

```
## Research Complete

I've saved detailed findings to `tasks/research-[feature-name].md`.

### Key Findings:
- [Most important finding 1]
- [Most important finding 2]
- [Most important finding 3]

### Recommended Approach:
[Brief recommendation]

### Potential Concerns:
- [Concern 1]
- [Concern 2]

Does this align with your understanding? Any areas I should investigate further before we proceed to the PRD?
```

Wait for user confirmation before proceeding to clarifying questions.

---

## Step 1: Clarifying Questions

Ask only critical questions where the initial prompt is ambiguous. Focus on:

- **Problem/Goal:** What problem does this solve?
- **Core Functionality:** What are the key actions?
- **Scope/Boundaries:** What should it NOT do?
- **Success Criteria:** How do we know it's done?

**If research was conducted:** Use the findings to ask more informed questions. Skip questions that were already answered by the research.

### Format Questions Like This:

```
1. What is the primary goal of this feature?
   A. Improve user onboarding experience
   B. Increase user retention
   C. Reduce support burden
   D. Other: [please specify]

2. Who is the target user?
   A. New users only
   B. Existing users only
   C. All users
   D. Admin users only

3. What is the overall scope?
   A. Minimal viable version
   B. Full-featured implementation
```

This lets users respond with "1A, 2C, 3B" for quick iteration. Remember to indent the options.

**Note:** You do NOT need to ask about backend vs frontend scope upfront. Instead, determine which layers each user story affects when writing the stories (see Step 2).

---

## Step 2: PRD Structure

Generate the PRD with these sections:

### 1. Introduction/Overview
Brief description of the feature and the problem it solves.

**If research was conducted:** Reference the research file and incorporate key findings.

### 2. Goals
Specific, measurable objectives (bullet list).

### 3. User Stories
Each story needs:
- **Title:** Short descriptive name
- **Description:** "As a [user], I want [feature] so that [benefit]"
- **Acceptance Criteria:** Verifiable checklist of what "done" means

Each story should be small enough to implement in one focused session.

**Format:**
```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Layers:** [Backend | Frontend | Both]

**Acceptance Criteria:**
- [ ] Specific verifiable criterion
- [ ] Another criterion
- [ ] Typecheck/lint passes
- [ ] **[Frontend/Both only]** Verify in browser using Chrome DevTools MCP
```

**Important:**
- **Layers field is required for each story.** This determines which development phases the story goes through:
  - `Backend` - Only backend dev and review (API, database, business logic)
  - `Frontend` - Only frontend dev and review (UI, components, styling)
  - `Both` - Full pipeline (backend dev → backend review → frontend dev → frontend review)
- Acceptance criteria must be verifiable, not vague. "Works correctly" is bad. "Button shows confirmation dialog before deleting" is good.
- **For any story with UI changes (Frontend or Both):** Always include "Verify in browser using Chrome DevTools MCP" as acceptance criteria.
- **If research was conducted:** Use findings to identify which files to modify, patterns to follow, and components to reuse.

### 4. Functional Requirements
Numbered list of specific functionalities:
- "FR-1: The system must allow users to..."
- "FR-2: When a user clicks X, the system must..."

Be explicit and unambiguous.

### 5. Non-Goals (Out of Scope)
What this feature will NOT include. Critical for managing scope.

### 6. Design Considerations (Optional)
- UI/UX requirements
- Link to mockups if available
- Relevant existing components to reuse

**If research was conducted:** Reference reusable components and patterns discovered.

### 7. Technical Considerations (Optional)
- Known constraints or dependencies
- Integration points with existing systems
- Performance requirements

**If research was conducted:** Include constraints and dependencies discovered during research.

### 8. Success Metrics
How will success be measured?
- "Reduce time to complete X by 50%"
- "Increase conversion rate by 10%"

### 9. Open Questions
Remaining questions or areas needing clarification.

### 10. Research Reference (If conducted)
If research was conducted, add:
```markdown
## Research Reference

See `tasks/research-[feature-name].md` for detailed codebase analysis and external research findings.
```

---

## Writing for Junior Developers

The PRD reader may be a junior developer or AI agent. Therefore:

- Be explicit and unambiguous
- Avoid jargon or explain it
- Provide enough detail to understand purpose and core logic
- Number requirements for easy reference
- Use concrete examples where helpful

---

## Output

- **Research (if conducted):** `tasks/research-[feature-name].md`
- **PRD:** `tasks/prd-[feature-name].md`
- **Format:** Markdown (`.md`)
- **Filename:** kebab-case

---

## Example PRD

```markdown
# PRD: Task Priority System

## Introduction

Add priority levels to tasks so users can focus on what matters most. Tasks can be marked as high, medium, or low priority, with visual indicators and filtering to help users manage their workload effectively.

## Goals

- Allow assigning priority (high/medium/low) to any task
- Provide clear visual differentiation between priority levels
- Enable filtering and sorting by priority
- Default new tasks to medium priority

## User Stories

### US-001: Add priority field to database
**Description:** As a developer, I need to store task priority so it persists across sessions.

**Layers:** Backend

**Acceptance Criteria:**
- [ ] Add priority column to tasks table: 'high' | 'medium' | 'low' (default 'medium')
- [ ] Generate and run migration successfully
- [ ] Typecheck passes

### US-002: Display priority indicator on task cards
**Description:** As a user, I want to see task priority at a glance so I know what needs attention first.

**Layers:** Frontend

**Acceptance Criteria:**
- [ ] Each task card shows colored priority badge (red=high, yellow=medium, gray=low)
- [ ] Priority visible without hovering or clicking
- [ ] Typecheck passes
- [ ] Verify in browser using Chrome DevTools MCP

### US-003: Add priority selector to task edit
**Description:** As a user, I want to change a task's priority when editing it.

**Layers:** Both

**Acceptance Criteria:**
- [ ] Priority dropdown in task edit modal
- [ ] Shows current priority as selected
- [ ] Saves immediately on selection change
- [ ] Typecheck passes
- [ ] Verify in browser using Chrome DevTools MCP

### US-004: Filter tasks by priority
**Description:** As a user, I want to filter the task list to see only high-priority items when I'm focused.

**Layers:** Both

**Acceptance Criteria:**
- [ ] Filter dropdown with options: All | High | Medium | Low
- [ ] Filter persists in URL params
- [ ] Empty state message when no tasks match filter
- [ ] Typecheck passes
- [ ] Verify in browser using Chrome DevTools MCP

## Functional Requirements

- FR-1: Add `priority` field to tasks table ('high' | 'medium' | 'low', default 'medium')
- FR-2: Display colored priority badge on each task card
- FR-3: Include priority selector in task edit modal
- FR-4: Add priority filter dropdown to task list header
- FR-5: Sort by priority within each status column (high to medium to low)

## Non-Goals

- No priority-based notifications or reminders
- No automatic priority assignment based on due date
- No priority inheritance for subtasks

## Technical Considerations

- Reuse existing badge component with color variants
- Filter state managed via URL search params
- Priority stored in database, not computed

## Success Metrics

- Users can change priority in under 2 clicks
- High-priority tasks immediately visible at top of lists
- No regression in task list performance

## Open Questions

- Should priority affect task ordering within a column?
- Should we add keyboard shortcuts for priority changes?
```

---

## Example Research Output

```markdown
# Research: Task Priority System

**Date:** 2026-02-05
**Feature:** Add priority levels (high/medium/low) to tasks

## Executive Summary

The codebase uses a standard React + PostgreSQL stack. Task data is stored in `tasks` table with existing columns for status and due_date. The Badge component in `src/components/ui/` supports color variants and can be reused for priority indicators. Similar filtering exists for task status that can be adapted.

## Codebase Analysis

### Relevant Files & Modules
- `src/db/schema/tasks.ts` - Task table definition, add priority column here
- `src/components/TaskCard.tsx` - Display component, add priority badge
- `src/components/ui/Badge.tsx` - Reusable badge with color variants
- `src/components/TaskList.tsx` - List component with existing status filter

### Existing Patterns
- **Database columns**: Use Drizzle ORM with `text()` type and `.default()` for enums
- **Filtering**: URL search params via `useSearchParams()` hook
- **UI Components**: Shadcn/ui components with Tailwind variants

### Reusable Components
- `Badge`: Already supports `variant` prop with colors (destructive, warning, secondary)
- `Select`: Dropdown component used for status filter

### Testing Approach
- Unit tests in `*.test.tsx` files alongside components
- E2E tests in `tests/e2e/` using Playwright

## External Research

### Official Documentation
- [Drizzle ORM Columns](https://orm.drizzle.team/docs/column-types): Use `text()` with check constraint for enum-like behavior

### GitHub Issues
- No existing issues for priority feature
- #45: Related discussion about task sorting (closed, implemented)

## Technical Considerations

### Constraints
- Must maintain backwards compatibility (existing tasks get 'medium' default)
- Filter must work with existing status filter (AND logic)

### Dependencies
- Drizzle ORM for migration
- Existing Badge and Select components

### Risks
- Performance: Adding filter may slow list queries (mitigate with index)

## Recommendations

### Suggested Approach
1. Add column with migration (default 'medium')
2. Update TaskCard to show badge
3. Add filter using existing pattern from status filter
4. Add to edit modal using existing Select component

### Files to Modify
- `src/db/schema/tasks.ts` - Add priority column
- `src/components/TaskCard.tsx` - Add priority badge
- `src/components/TaskList.tsx` - Add priority filter
- `src/components/TaskEditModal.tsx` - Add priority selector

### Files to Create
- `src/db/migrations/0002_add_priority.ts` - Migration file

## Open Questions

- Should we add a database index on priority for filter performance?
- Should priority be included in task search results?
```

---

## Checklist

Before saving the PRD:

- [ ] Asked if user wants research (for complex features)
- [ ] If research requested: Conducted thorough investigation and saved to `tasks/research-[feature-name].md`
- [ ] Asked clarifying questions with lettered options
- [ ] Incorporated user's answers (and research findings if applicable)
- [ ] User stories are small and specific
- [ ] Each user story has a Layers field (Backend | Frontend | Both)
- [ ] Functional requirements are numbered and unambiguous
- [ ] Non-goals section defines clear boundaries
- [ ] Saved PRD to `tasks/prd-[feature-name].md`
