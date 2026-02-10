---
description: Transition from planning to execution after user approval
---

# Proceed Workflow (Amkabot)

Standardizes the handoff from design to implementation.

## 1. Pre-requisites
- [ ] User has approved the `implementation_plan.md`.
- [ ] All blockers identified in planning are resolved.

## 2. Initialization
- Update `task.md` with granular implementation steps.
- Set `task_boundary` to `EXECUTION` mode.

## 3. Implementation
- Follow the plan file-by-file.
- Maintain the "Functional Core, Imperative Shell" pattern.
- Integrate unit tests concurrently with feature development.

## 4. Feedback Loop
- If technical complexity increases beyond the plan, revert to `PLANNING` and update docs.
