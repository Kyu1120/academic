# Codex repository instructions — Integrated Math Progress Planner

## Mission
Build a working, teacher-facing MVP for an adaptive mathematics learning schedule planner. Read `CODEX_TASK.md` first, then `architecture.md` and `schema.sql`. The supplied documents are the specification and schema drafts, **not** an implemented application.

## Engineering requirements
- Write maintainable Python code with type hints and small, testable functions. Use FastAPI for the backend, PostgreSQL persistence, and Streamlit for the initial teacher UI. Prefer simple, well-supported dependencies.
- Keep hard constraints and numerical scheduling in deterministic application code. Do not use an LLM as the source of truth for student mastery, arithmetic, or scheduling.
- Separate syllabus coverage from concept readiness; do not equate completed pages with mastery.
- Preserve actual lesson records and approved plans. Regeneration creates a new draft version; teacher review/approval is required.
- Treat deadlines and teacher-locked activities as hard constraints unless explicitly relaxed by the teacher. If a plan is infeasible, report unallocated work and the time shortfall; never silently drop tasks or distort results.
- Respect timezone-aware lesson timestamps and academy timezone (default Asia/Seoul). Use a consistent date boundary for due dates.
- Validation is mandatory (student/goal/lesson consistency, no double-count of imported progress, available minutes, planned units, and item order). Check for cross-academy data access before exposing real records.
- Do not introduce third-party model calls or process actual children's personal information by default. Populate only synthetic fixtures in demo mode.
- Start with the existing `schema.sql` as a source of truth but review it for necessary changes, including constraints and safe migrations. Explain any changes in the documentation.
- Add tests for core planner logic, API integration, and critical edge cases. Run tests when possible and report which checks actually ran.

## Scope discipline
- Implement Phase 1 defined in `CODEX_TASK.md` completely before attempting skill-level adaptive algorithms, machine learning, OR-Tools, LLM, parent portal, advanced auth, or deployment.
- A usable local demo is more important than elaborate abstractions. Do not replace implementation with more planning documents.
- Record all assumptions, actual run steps, and remaining risks in `README.md`.
