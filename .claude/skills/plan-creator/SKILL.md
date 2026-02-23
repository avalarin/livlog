---
name: plan-creator
description: Guide for describing plans (researches, tasks). This skill should be used when users want to get a plan descritpion to research soluctions, develop feature or solve problem. The result is a file in directory `./.claude/plans/`.
---

# Plan Creator

This skill provices guidance for creating plans (researches, tasks).

## About Plans

Plans are meant to help the user confirm that everything will be done exactly the way they expect.

Each plan should include a complete description, with links to the files and the specific code sections that will be changed. If the changes affect API design, database design, or other complex areas (like authentication, encryption, or a non-trivial algorithm), include a clear explanation of the proposed solution.

Checklist for a good plan description:
- Detailed enough, but still short;
- No large, full code blocks—only small snippets when needed to show the solution logic;
- No repeated text; keep it tight and to the point;
- Plan description in the same language the user asked the question in.

## Templates
In the skill folder, there’s a `./templates` directory with plan templates:
- `task.md` — works when you need to describe a task for a developer;
- `research.md` - works when the user asks you to investigate something and give a report.

### Good examples of choosing templates
> User (rus): **опиши задачу**, нужно сделать авторизацию
> User (eng): **describe the task**, we need to implement authentication  
> Agent: I’m choosing the task.md template because we need to write up a task for a developer

> User (rus): **исследуй** как сделать авторизацию
> User: (eng) **research** how to implement authentication  
> Agent: I’m choosing the research.md template because the user is asking to do research

IMPORTANT: Always use the templates when writing plan descriptions.

## How to elaborate the solution
Describe the following parts:
-  Briefly describe the plan
-  Functional requirements: what functions must be included
-  Non-functional requirements: performance, security
-  Acceptance criteria: how to verify that everything works
-  Step-by-step solution: in what order and what needs to be done to complete the plan
-  Test automation plan: what automated tests need to be written to verify that everything works

## How to create plan file

1. **Find Next Number**:
   - Read existing files in `./.claude/plans/`
   - Find the maximum number
   - Use next sequential number

2. **Create Filename**:
   - Format: `{number}-{template}-{kebab-case-name}.md`
   - Example: `13-task-add-dark-mode.md` or `14-research-fix-image-loading.md`

3. **Fill Template**: Use the template from `.templates` dir, check instruction about templates above.

## Final checklist
- [ ] There’s a file in the `./.claude/plans/` folder at the project root.
- [ ] The file is based on one of the templates listed in the **Templates** section.
- [ ] The file contains a clear, complete description of the plan to be done.
- [ ] Plan description in the same language the user asked the question in.
