# Codex implementation task — Math Progress Planner MVP

## User objective
Create a working web application that makes individual mathematics learning schedules for academy students. A teacher inputs student, textbook sections, actual progress, lesson calendar, and a completion deadline. The application creates a per-lesson learning plan, reports whether the goal is achievable, and recalculates the future plan when a lesson finishes or a session is cancelled. Teacher approval is required to publish a new plan.

Existing source documents:
- `architecture.md`: detailed functional/technical specification; Phase 1 is current implementation scope.
- `schema.sql`: PostgreSQL domain model (21 tables, one view). Use as starting point, not evidence of a running DB.
- `AGENTS.md`: durable project instructions.

## Deliver actual runnable code, not just a new design
### 1. Local runnable environment
- Backend: Python 3.12+, FastAPI, SQLAlchemy or SQLModel, PostgreSQL. Provide migration/bootstrap procedure.
- Teacher interface: Streamlit that communicates with the FastAPI app; no hardcoded fake API calls in the happy path.
- `docker-compose.yml` for Postgres; `.env.example`, `requirements` or `pyproject.toml`, startup commands, and a `README.md`.
- No authentication is required for an isolated synthetic-data **local demo only**. Display a warning in the UI/documentation that it is not safe to publish online or use with real students without proper authentication, tenant separation, and access control. If auth is added, do not bypass it.

### 2. Working teacher flows
- Create/view/edit student basic profile with generated student code, grade (avoid collecting student phone/address), and assign textbook.
- Register textbook with ordered sections, work unit type (page, problem_set, worksheet), total units, and initial baseline minutes. Provide demo seed data and optionally CSV import.
- Record imported starting progress for a student; never double count subsequently recorded activity.
- Register one or more learning goals with target completion date and selected textbook sections.
- Create and cancel dated lesson sessions (Asia/Seoul display), each with `available_minutes`. Allow listing upcoming sessions.
- Generate an ordered per-lesson draft plan with allocations and reasons, show required time, reserve time, available time and **shortfall**. A feasible time budget alone must not be described as verified mastery.
- Edit/lock draft plan items if practical; approve a draft; preserve approved-plan history. No silent modification of already approved snapshots.
- Record completed lesson activity (section, type, units, minutes), show observed progress, and trigger **new draft** from future lessons only; teacher must approve the new draft. Treat earlier actual lessons as immutable.
- Dashboard: progress by section, goal deadline, planned vs available time, unmet allocation, approved vs draft plan.

### 3. Deterministic Phase 1 scheduling algorithm
- An ordered list of target sections is defined by textbook section sequence number (and explicit goal priorities, if needed). Preserve teacher-locked items and completed sessions.
- Remaining units = `max(0, total_units - min(total_units, initial_baseline_units + actual_new_learning_units))`.
- Estimated new-learning minutes = `ceil(section.baseline_minutes * remaining_units/total_units * speed_factor)`; start `speed_factor=1.0` when observations are insufficient. Use a documented, bounded and explainable estimator if observations exist; no black-box predictive claims.
- Available target sessions = scheduled sessions within planning horizon and on/before goal due date, excluding cancelled/completed sessions.
- Reserve ratio defaults to 10% of future session capacity; report gross capacity and net usable minutes separately. Allocate never beyond the post-reserve per-session effective capacity, using a deterministic rounding strategy.
- Split sections across sessions by work-unit boundaries. Do not allocate more remaining units than exist, and do not allocate time beyond per-session usable capacity. Handle tiny capacity and discrete work units explicitly; residual unused minutes are acceptable.
- If requested target work cannot be allocated by deadline, return a clear infeasible result including unallocated units and estimated shortage; do not throw away remaining items silently.
- If already completed by imported/current progress, return zero new work and an appropriate summary.
- Deterministic tie breaking, clear reason codes, and a repeatable plan with unchanged input. Do not accidentally reuse mutable planned quantities as actual progress.
- Keep readiness/mastery as `unknown` without assessment records; do not mark them as `mastered` based on page coverage.

### 4. Tests (must be automated)
1. Three 90-min sessions; 10% reserve; 260 min needed => capacity 243 min and 17 min shortfall (for this aggregate capacity calculation).
2. No lessons left before goal deadline => infeasible if work remains.
3. No work remaining => zero scheduled new work.
4. Cancelled lesson creates a draft replan that leaves historic actual records untouched.
5. Imported baseline plus new learning does not exceed section total or count review as progress.
6. A plan never assigns more than each session's net usable minutes or more work units than remain.
7. Identical inputs produce identical ordered allocations even if record creation order differs.
8. Approved plan is not overwritten by regeneration; both versions can be inspected.
9. Attempt to save an activity against the wrong student's lesson/section fails validation.
10. Locked draft/previously approved items are preserved when replanning, or conflicts are clearly surfaced as infeasibility.

### 5. Acceptance checklist
- From a clean checkout, instructions suffice to start Postgres, backend, and Streamlit and open the dashboard.
- A synthetic student can be created, given a book/goal, planned, simulated as completing a lesson, then replanned and approved end-to-end.
- Test suite executes and passes, or the specific unmet environment prerequisite is documented.
- No hardcoded real student names or personally identifying student data are included.
- A concise report states created files, run/test commands, changes to original schema, and known issues.

## Expected execution approach
1. Inspect existing two source documents and confirm major constraints / schema caveats.
2. Implement minimal working backend, schema/migrations, deterministic planner, tests, seed data, then the teacher UI. Prioritize vertical slices over scaffolding.
3. Run available tests/linters/smoke checks, fix actual errors, and update the README with exact local setup.
4. Stop after the functional Phase 1 MVP. Clearly label future items: adaptive skill assessments, ML, OR-Tools and AI narrative explanation.

Do not merely respond with a plan. Write the project files and verify as much as your execution environment permits.
