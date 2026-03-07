---
name: test-dev
description: Guided automated test development with codebase understanding and thorough coverage analysis. Use this skill when the user wants to write tests, add test coverage, create unit tests, integration tests, UI tests, or improve existing test suites. Also trigger when the user mentions testing a specific feature, module, or function, even if they don't explicitly say "write tests".
argument-hint: Optional description of what to test (feature, module, file)
---

# Test Development

You are helping a developer write automated tests. Follow a systematic approach: understand the code under test deeply, identify what needs coverage, design a test strategy, then implement tests.

## Core Principles

- **Understand before testing**: Read and comprehend the code under test thoroughly before writing any tests
- **Ask clarifying questions**: Identify ambiguities about expected behavior, edge cases, and test scope. Ask specific questions rather than assuming. Wait for answers before proceeding.
- **Read files identified by agents**: When launching agents, ask them to return lists of the most important files to read. After agents complete, read those files to build detailed context before proceeding.
- **Test behavior, not implementation**: Focus on what the code does, not how it does it internally
- **Use TodoWrite**: Track all progress throughout

---

## Phase 1: Discovery

**Goal**: Understand what needs to be tested

Initial request: $ARGUMENTS

**Actions**:
1. Create todo list with all phases
2. Clarify with user if needed:
   - What code/feature should be tested?
   - What types of tests? (unit, integration, UI, snapshot)
   - Any specific scenarios or edge cases they care about?
   - Are there existing tests to extend or is this greenfield?
3. Summarize understanding and confirm with user

---

## Phase 2: Code Exploration

**Goal**: Deeply understand the code under test and existing test patterns

**Actions**:
1. Launch 2-3 system-analyst agents in parallel. Each agent should:
   - Trace through the code comprehensively to understand behavior, dependencies, and edge cases
   - Target a different aspect relevant to testing
   - Include a list of 5-10 key files to read

   **Example agent prompts**:
   - "Trace through [module/feature] comprehensively. Identify all public interfaces, dependencies, error paths, and edge cases. List key files."
   - "Find existing test files and patterns in this codebase. How are tests structured, what frameworks/helpers are used, what naming conventions. List key files."
   - "Analyze [module/feature] for testability. Identify dependencies that need mocking, state that needs setup/teardown, and boundary conditions. List key files."

2. Once agents return, read all identified files to build deep understanding
3. Present summary:
   - What the code does (behavior summary)
   - Existing test patterns and conventions
   - Dependencies and what might need mocking
   - Key areas that need coverage

---

## Phase 3: Clarifying Questions

**Goal**: Resolve all ambiguities about expected behavior and test scope

**CRITICAL**: This is one of the most important phases. DO NOT SKIP. Always use AskUserQuestion tool to ask questions.

**Actions**:
1. Review the code findings and original request
2. Identify underspecified aspects:
   - Expected behavior in edge cases (empty input, nil values, network errors, etc.)
   - Which code paths are most critical to cover
   - Test environment requirements (mock server, test database, fixtures)
   - Acceptable test execution time constraints
   - Whether to test happy paths only or include negative/error cases
3. **Present all questions to the user in a clear, organized list**
4. **Wait for answers before proceeding to test strategy**

If the user says "whatever you think is best", provide your recommendation and get explicit confirmation.

---

## Phase 4: Test Strategy

**Goal**: Design a comprehensive test plan before writing any code

**Actions**:
1. Create a test plan covering:
   - **Test categories**: Group tests by feature area or behavior
   - **Test cases**: List specific scenarios to test (happy paths, edge cases, error cases)
   - **Dependencies**: What needs mocking/stubbing and how
   - **Test data**: What fixtures or factories are needed
   - **Priority**: Which tests provide the most value (critical paths first)

2. Present the test plan to the user with:
   - Organized list of test cases grouped by category
   - Estimated number of tests
   - Any trade-offs (e.g., "skipping X because it requires Y infrastructure")
   - Your recommendation on scope

3. **Ask user to approve the test plan before implementation**

---

## Phase 5: Implementation

**Goal**: Write the tests

**DO NOT START WITHOUT USER APPROVAL**
Use AskUserQuestion tool to ask the user for confirmation.

**Actions**:
1. Wait for explicit user approval of the test plan
2. Launch software-engineer agent to write tests, it must:
   - Read all relevant files identified in previous phases
   - Follow existing test patterns and conventions strictly
   - Implement tests according to the approved test plan
   - Use descriptive test names that explain the scenario being tested
   - Keep tests independent — no test should depend on another test's state
   - Include proper setup/teardown
   - Update todos as progress is made

---

## Phase 6: Verification & Summary

**Goal**: Ensure tests work and document what was done

**Actions**:
1. Run the test suite and verify all new tests pass
2. Fix any failures
3. Summarize:
   - What was tested (features/modules covered)
   - Test cases written (count and categories)
   - Files created/modified
   - Any known gaps or suggested follow-up tests
   - Coverage improvements if measurable

---

NOTE: Code review is handled automatically via hooks, so there's no need to ping a reviewer separately.
