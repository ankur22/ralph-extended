# Phase 3 Complete: QA Agent with k6 Integration

## Overview

Phase 3 extends the Ralph Extended system with automated QA testing using k6. The QA agent executes functional API tests and e2e browser tests, identifies issues, and routes them back to the appropriate development agent (backend or frontend).

## What Was Built

### 1. QA Agent (QA.md)
A specialized QA engineer agent that:
- Executes k6 functional tests (API testing)
- Executes k6 browser tests (e2e UI testing)
- Analyzes test results and categorizes failures by layer (backend vs frontend)
- Routes issues back to appropriate development agents
- Updates tracking files with test results
- Handles edge cases (no testing needed, max cycles, flaky tests)

### 2. Test Configuration System (tests.json)
Structured test configuration for each feature:
- **Functional tests**: API endpoints, expected responses, thresholds
- **E2E tests**: User scenarios, browser flows, accessibility checks
- **Config**: Base URL, timeouts, retries, parallel execution settings

### 3. k6 Test Templates
Ready-to-use templates for creating tests:
- `template-functional.js`: API testing template with k6 http module
- `template-e2e.js`: Browser testing template with k6 browser module
- `README.md`: Complete guide for running and creating tests

### 4. Orchestrator Integration
Enhanced `ralph-extended.sh` with:
- QA state handling (qa_testing, qa_passed, qa_issues_backend, qa_issues_frontend)
- Auto-transition from frontend_review_passed → qa_testing
- Issue routing logic based on layer categorization
- QA cycle tracking with max cycles protection
- Feature completion now requires QA pass (not just frontend pass)

### 5. Extended Tracking
Updated `feature_progress.json` structure:
- QA history entries with test results (functional + e2e)
- Test pass/fail counts and durations
- Issue layer categorization (backend/frontend)
- QA-specific issues array
- Config for maxQACycles and skipQAAfterMax

### 6. Developer Agent Updates
Both backend and frontend agents now handle:
- QA failure routing
- Issue categorization from QA tests
- Return to QA after fixes

## Complete State Flow

```
┌─────────────┐
│ Feature     │
│ Start       │
└──────┬──────┘
       │
       v
┌─────────────────────────────────────────────────────────────┐
│ Backend Phase                                                 │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐      ┌──────────────┐                     │
│  │ Backend Dev  │─────>│ Backend      │                     │
│  │              │      │ Review       │                     │
│  └──────────────┘      └──────┬───────┘                     │
│         ^                     │                              │
│         │                     │ passed                       │
│         │ failed              v                              │
│         └─────────────────────┘                              │
│                                                               │
└────────────────────────┬──────────────────────────────────────┘
                         │ auto-transition
                         v
┌─────────────────────────────────────────────────────────────┐
│ Frontend Phase                                                │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐      ┌──────────────┐                     │
│  │ Frontend Dev │─────>│ Frontend     │                     │
│  │              │      │ Review       │                     │
│  └──────────────┘      └──────┬───────┘                     │
│         ^                     │                              │
│         │                     │ passed                       │
│         │ failed              v                              │
│         └─────────────────────┘                              │
│                                                               │
└────────────────────────┬──────────────────────────────────────┘
                         │ auto-transition
                         v
┌─────────────────────────────────────────────────────────────┐
│ QA Phase                                                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ QA Testing                                            │   │
│  │                                                       │   │
│  │  • Run k6 functional tests (API)                     │   │
│  │  • Run k6 browser tests (e2e UI)                     │   │
│  │  • Analyze results                                    │   │
│  │  • Categorize failures                                │   │
│  └──────┬────────────────────────────────────┬──────────┘   │
│         │                                    │               │
│         │ backend issues                     │ all passed    │
│         v                                    v               │
│    Backend Dev                          QA Passed            │
│    (QA Fixes)                           (Complete!)          │
│         │                                    │               │
│         └─> Backend Review ─> QA Testing ───┘               │
│                                                               │
│         │ frontend issues                                    │
│         v                                                     │
│    Frontend Dev                                               │
│    (QA Fixes)                                                 │
│         │                                                     │
│         └─> Frontend Review ─> QA Testing                    │
│                                                               │
│                                                               │
│  Special Cases:                                               │
│  • QA_NO_TESTING → qa_passed (skip testing)                 │
│  • QA_PASSED_MAX_CYCLES → qa_passed (max cycles reached)    │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

## Test Execution Strategy

### Functional Tests (k6 HTTP)
Target: Backend API endpoints
- Test status codes (200, 400, 404, 500)
- Validate response schemas
- Check performance thresholds (p95 < 500ms)
- Test error handling
- Verify authentication/authorization
- Test edge cases (empty input, special characters, etc.)

Example:
```bash
k6 run tests/k6/us-001-functional.js
```

### E2E Tests (k6 Browser)
Target: Frontend UI and user flows
- Navigate to pages
- Interact with UI elements (click, type, submit)
- Verify element visibility and state
- Test form validation
- Check loading states
- Verify error messages
- Test accessibility (ARIA labels, keyboard navigation)

Example:
```bash
k6 run tests/k6/us-001-e2e.js
```

## Issue Categorization Logic

### Backend Issues (Route to Backend Dev)
- API returns wrong status code (4xx/5xx)
- API timeout or connection errors
- Response schema doesn't match expected
- Missing or incorrect fields in response
- Database errors or slow queries
- Authentication/authorization failures at API level
- Performance issues (slow response times)

### Frontend Issues (Route to Frontend Dev)
- UI element not found or not visible
- Incorrect rendering or layout issues
- JavaScript errors in browser console
- Form validation not working
- Client-side state management issues
- Loading state not shown
- Error messages not displayed
- Accessibility violations
- Navigation or routing issues

### Mixed Issues (Both Layers)
When both backend and frontend issues are present:
1. Route to backend first (backend is dependency for frontend)
2. After backend fixes pass QA, frontend issues will be caught in next QA run

## Edge Cases Handled

### 1. No QA Testing Needed
Scenario: Feature is internal refactoring with no external behavior changes

Behavior:
- QA agent detects no user-facing changes
- Outputs `QA_NO_TESTING`
- Updates feature_progress.json with explanation
- Transitions to `qa_passed` state
- Feature marked complete

### 2. Max QA Cycles Reached
Scenario: Feature has been through 5+ QA cycles (maxQACycles)

Behavior:
- Check if remaining issues are minor (P2/P3)
- If yes: Approve with warning (`QA_PASSED_MAX_CYCLES`)
- If critical bugs remain: Continue routing to dev agents
- Safety override: Do not approve broken features

### 3. Service Fails to Start
Scenario: Backend service crashes or fails to start

Behavior:
- Categorize as backend issue
- Route to Backend Dev with specific error
- Dev fixes startup issues
- Returns to QA after fix

### 4. Flaky Tests
Scenario: Test occasionally fails due to timing or race conditions

Behavior:
- Use `config.retries` (default: 2) to retry failed tests
- If passes on retry: Note flakiness in progress.txt
- If consistently fails: Route as real issue
- Recommend improving test reliability

### 5. Missing Test Scripts
Scenario: No k6 test script exists for feature

Behavior:
- QA agent creates test configuration in tests.json
- Creates k6 test scripts based on acceptance criteria
- Uses templates (template-functional.js, template-e2e.js)
- Commits test scripts with feature

### 6. Partial Implementation
Scenario: Backend implemented but no frontend (or vice versa)

Behavior:
- Test only implemented layers
- Skip e2e tests if no frontend UI exists
- Skip functional tests if no backend API exists
- Note in progress.txt which tests were skipped and why

### 7. Both Backend and Frontend Issues
Scenario: Tests reveal issues in both layers

Behavior:
- Route to backend first (dependency order)
- Backend dev fixes and commits
- Returns to QA testing
- QA retests everything (functional + e2e)
- If frontend issues still present: Route to frontend dev
- Frontend dev fixes and commits
- Returns to QA testing again

## Testing Recommendations

### Creating Tests
1. Read acceptance criteria carefully
2. Create test suite in `tests.json`
3. Write k6 functional tests for each API endpoint
4. Write k6 e2e tests for each user scenario
5. Set appropriate thresholds (response time, error rate)
6. Test happy path AND error cases
7. Test edge cases (empty input, special characters, etc.)

### Running Tests Locally
```bash
# Start services first
make run  # or equivalent for your project

# Run functional tests
k6 run tests/k6/us-001-functional.js

# Run e2e tests
k6 run tests/k6/us-001-e2e.js

# Run with custom base URL
BASE_URL=http://localhost:3000 k6 run tests/k6/us-001-functional.js
```

### Test Quality Guidelines
- **Specific**: Test one thing per check
- **Reliable**: No flaky tests (use waits for async operations)
- **Fast**: Keep test duration reasonable (< 30s per test)
- **Clear**: Descriptive check names and error messages
- **Complete**: Cover all acceptance criteria

## Example Test Scenarios

### Scenario 1: Health Endpoint
Feature: Backend health check endpoint

Functional test:
```javascript
// GET /health returns 200
// Response includes status and database fields
// Response time < 500ms
const res = http.get(`${BASE_URL}/health`);
check(res, {
  'status is 200': (r) => r.status === 200,
  'has status field': (r) => JSON.parse(r.body).status !== undefined,
  'has database field': (r) => JSON.parse(r.body).database !== undefined,
});
```

E2E test:
```javascript
// Navigate to dashboard
// Health status card is visible
// Status shows "healthy" or "unhealthy"
await page.goto('http://localhost:8080/dashboard');
const healthCard = page.locator('[data-testid="health-card"]');
await healthCard.waitFor();
check(healthCard, {
  'health card visible': (card) => card.isVisible(),
});
```

### Scenario 2: User Login
Feature: User authentication with JWT

Functional test:
```javascript
// POST /api/auth/login with valid credentials returns 200
// Response includes token, refreshToken, expiresIn
// POST /api/auth/login with invalid credentials returns 401
const validRes = http.post(`${BASE_URL}/api/auth/login`, JSON.stringify({
  username: 'testuser',
  password: 'testpass',
}), { headers: { 'Content-Type': 'application/json' } });

check(validRes, {
  'valid login returns 200': (r) => r.status === 200,
  'returns token': (r) => JSON.parse(r.body).token !== undefined,
});

const invalidRes = http.post(`${BASE_URL}/api/auth/login`, JSON.stringify({
  username: 'wrong',
  password: 'wrong',
}), { headers: { 'Content-Type': 'application/json' } });

check(invalidRes, {
  'invalid login returns 401': (r) => r.status === 401,
});
```

E2E test:
```javascript
// Navigate to login page
// Enter credentials and submit
// Loading state is shown
// Redirects to dashboard on success
// Token stored in localStorage
await page.goto('http://localhost:8080/login');
await page.locator('input[name="username"]').type('testuser');
await page.locator('input[name="password"]').type('testpass');
await page.locator('button[type="submit"]').click();

// Check loading state appears
const loadingSpinner = page.locator('[data-testid="loading"]');
check(loadingSpinner, {
  'loading state shown': (spinner) => spinner.isVisible(),
});

// Wait for redirect
await page.waitForURL('**/dashboard');
check(page, {
  'redirected to dashboard': (p) => p.url().includes('/dashboard'),
});
```

## File Structure

```
ralph-extended/
├── QA.md                           # QA agent prompt
├── BACKEND_DEV.md                  # Updated with QA section
├── FRONTEND_DEV.md                 # Updated with QA section
├── ralph-extended.sh               # Updated orchestrator
├── tests.json.example              # Test configuration example
├── feature_progress.json.example   # Updated with QA examples
├── PHASE3_COMPLETE.md             # This document
└── test-project/
    ├── tests.json                  # Initial test config
    └── tests/
        └── k6/
            ├── template-functional.js
            ├── template-e2e.js
            └── README.md
```

## Next Steps (Phase 4 Possibilities)

### Option 1: Deployment Agent
Add automated deployment phase after QA passes:
- Deploy to staging environment
- Run smoke tests
- Deploy to production
- Rollback on failure

### Option 2: Performance Testing
Enhance QA agent with load testing:
- k6 load tests with multiple VUs
- Stress testing
- Spike testing
- Performance regression detection

### Option 3: Security Testing
Add security scanning phase:
- OWASP dependency check
- Static code analysis for vulnerabilities
- API security testing
- Secrets detection

### Option 4: Documentation Agent
Add automated documentation updates:
- API documentation (OpenAPI/Swagger)
- Changelog updates
- README updates
- Architecture diagrams

### Option 5: Monitoring & Observability
Add post-deployment monitoring:
- Health check validation
- Error rate monitoring
- Performance metrics
- Alert integration

## Success Criteria

Phase 3 is complete when:
- ✅ QA.md exists with complete workflow
- ✅ ralph-extended.sh handles all QA states
- ✅ tests.json structure documented and working
- ✅ QA agent can execute k6 functional tests
- ✅ QA agent can execute k6 browser tests
- ✅ Issues correctly routed to backend vs frontend
- ✅ Max cycles protection works
- ✅ "No QA needed" path works
- ✅ Complete flow (Backend → Frontend → QA) works end-to-end
- ✅ Edge cases handled (service failure, flaky tests, missing scripts)
- ✅ PHASE3_COMPLETE.md documents the system

## Migration Guide

To migrate existing projects to Phase 3:

1. Copy new files:
   ```bash
   cp QA.md your-project/
   cp tests.json.example your-project/
   cp ralph-extended.sh your-project/
   ```

2. Update feature_progress.json:
   ```bash
   # Add config section
   jq '.config.maxQACycles = 5 | .config.skipQAAfterMax = true' \
     feature_progress.json > feature_progress.json.tmp
   mv feature_progress.json.tmp feature_progress.json
   ```

3. Create test directories:
   ```bash
   mkdir -p tests/k6
   cp test-project/tests/k6/*.js tests/k6/
   cp test-project/tests/k6/README.md tests/k6/
   ```

4. Create tests.json:
   ```bash
   cat > tests.json <<EOF
   {
     "testSuites": {},
     "config": {
       "baseUrl": "http://localhost:8080",
       "timeout": 30000,
       "retries": 2,
       "parallelExecution": false,
       "maxQACycles": 5
     }
   }
   EOF
   ```

5. Update current features in progress:
   - If feature is at `frontend_review_passed` state
   - Manually transition to `qa_testing` state
   - Run orchestrator to pick up QA phase

6. Install k6:
   ```bash
   # macOS
   brew install k6

   # Linux
   sudo gpg -k
   sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
     --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
   echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
     sudo tee /etc/apt/sources.list.d/k6.list
   sudo apt-get update
   sudo apt-get install k6
   ```

## Conclusion

Phase 3 completes the Ralph Extended multi-agent system with automated QA testing. The system now provides end-to-end autonomous development from feature implementation through code review to quality assurance testing.

Key achievements:
- ✅ Automated functional and e2e testing with k6
- ✅ Intelligent issue routing by layer
- ✅ Complete state flow from dev to deployment-ready
- ✅ Edge case handling for real-world scenarios
- ✅ Extensible test configuration system

The system is now production-ready for autonomous feature development with quality guarantees.
