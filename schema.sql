-- Integrated Math Progress Planner -- PostgreSQL 15+
-- Dates and times: store lesson timestamps as timestamptz (UTC normalized).
-- IANA timezone: academy.timezone (default Asia/Seoul).
-- This schema creates storage, not prediction/authorization/business-rule code.
BEGIN;

CREATE TABLE academies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    timezone text NOT NULL DEFAULT 'Asia/Seoul',
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE teachers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    academy_id uuid NOT NULL REFERENCES academies(id),
    auth_subject text NOT NULL UNIQUE,
    display_name text NOT NULL,
    role text NOT NULL DEFAULT 'teacher' CHECK (role IN ('owner','admin','teacher')),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(id, academy_id)
);

CREATE TABLE students (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    academy_id uuid NOT NULL REFERENCES academies(id),
    student_code text NOT NULL,
    display_name text NOT NULL,
    grade_code text NOT NULL,
    enrolled_on date,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(academy_id, student_code),
    UNIQUE(id, academy_id)
);

CREATE TABLE teacher_student_assignments (
    teacher_id uuid NOT NULL REFERENCES teachers(id),
    student_id uuid NOT NULL REFERENCES students(id),
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(teacher_id, student_id)
);

-- Catalogs: lesson units and skills are intentionally separate.
CREATE TABLE textbooks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL,
    publisher text,
    edition text NOT NULL,
    grade_code text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(title, edition, grade_code)
);

CREATE TABLE textbook_sections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    textbook_id uuid NOT NULL REFERENCES textbooks(id),
    section_code text NOT NULL,
    title text NOT NULL,
    sequence_no integer NOT NULL CHECK(sequence_no > 0),
    page_start integer,
    page_end integer,
    work_unit_type text NOT NULL DEFAULT 'page' CHECK(work_unit_type IN ('page','problem_set','worksheet')),
    work_units_total integer NOT NULL CHECK(work_units_total > 0),
    baseline_minutes integer NOT NULL CHECK(baseline_minutes > 0),
    difficulty smallint NOT NULL DEFAULT 3 CHECK(difficulty BETWEEN 1 AND 5),
    UNIQUE(textbook_id, section_code),
    UNIQUE(textbook_id, sequence_no),
    CHECK(page_start IS NULL OR page_start > 0),
    CHECK(page_end IS NULL OR (page_start IS NOT NULL AND page_end >= page_start))
);

CREATE TABLE skills (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    skill_code text NOT NULL UNIQUE,
    curriculum_version text NOT NULL,
    grade_code text,
    title text NOT NULL
);

CREATE TABLE skill_prerequisites (
    skill_id uuid NOT NULL REFERENCES skills(id),
    prerequisite_skill_id uuid NOT NULL REFERENCES skills(id),
    PRIMARY KEY(skill_id, prerequisite_skill_id),
    CHECK(skill_id <> prerequisite_skill_id)
    -- Application validation must prohibit longer directed cycles.
);

CREATE TABLE section_skills (
    section_id uuid NOT NULL REFERENCES textbook_sections(id),
    skill_id uuid NOT NULL REFERENCES skills(id),
    is_primary boolean NOT NULL DEFAULT true,
    PRIMARY KEY(section_id, skill_id)
);

CREATE TABLE student_textbooks (
    student_id uuid NOT NULL REFERENCES students(id),
    textbook_id uuid NOT NULL REFERENCES textbooks(id),
    started_on date NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','completed','paused')),
    PRIMARY KEY(student_id, textbook_id)
);

-- Use only for historical progress at the time of onboarding. Do not import
-- the same past activity again into lesson_activities or it will be double counted.
CREATE TABLE student_section_progress_baselines (
    student_id uuid NOT NULL REFERENCES students(id),
    section_id uuid NOT NULL REFERENCES textbook_sections(id),
    completed_work_units integer NOT NULL CHECK(completed_work_units >= 0),
    imported_on date NOT NULL,
    note text,
    PRIMARY KEY(student_id, section_id)
);

-- Optional weekly template; lesson_sessions are the scheduling source of truth.
CREATE TABLE weekly_schedules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES students(id),
    teacher_id uuid REFERENCES teachers(id),
    weekday smallint NOT NULL CHECK(weekday BETWEEN 0 AND 6), -- Mon=0
    starts_at_local time NOT NULL,
    duration_minutes integer NOT NULL CHECK(duration_minutes BETWEEN 1 AND 600),
    effective_from date NOT NULL,
    effective_until date,
    CHECK(effective_until IS NULL OR effective_until >= effective_from)
);

CREATE TABLE lesson_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES students(id),
    teacher_id uuid REFERENCES teachers(id),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    available_minutes integer NOT NULL CHECK(available_minutes > 0),
    status text NOT NULL DEFAULT 'scheduled' CHECK(status IN ('scheduled','completed','cancelled')),
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK(ends_at > starts_at),
    CHECK(available_minutes <= EXTRACT(EPOCH FROM (ends_at - starts_at)) / 60),
    UNIQUE(student_id, starts_at)
    -- Overlap of sessions must also be rejected by a service check or exclusion constraint.
);

CREATE TABLE learning_goals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES students(id),
    title text NOT NULL,
    goal_type text NOT NULL CHECK(goal_type IN ('textbook_completion','exam','custom')),
    due_on date NOT NULL,
    priority smallint NOT NULL DEFAULT 3 CHECK(priority BETWEEN 1 AND 5),
    target_mastery numeric(4,3) NOT NULL DEFAULT 0.800
        CHECK(target_mastery BETWEEN 0 AND 1),
    status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','achieved','cancelled')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE goal_sections (
    goal_id uuid NOT NULL REFERENCES learning_goals(id),
    section_id uuid NOT NULL REFERENCES textbook_sections(id),
    priority smallint NOT NULL DEFAULT 3 CHECK(priority BETWEEN 1 AND 5),
    PRIMARY KEY(goal_id, section_id)
);

-- Actual learning activity is never overwritten when plans are regenerated.
CREATE TABLE lesson_activities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    lesson_id uuid NOT NULL REFERENCES lesson_sessions(id),
    section_id uuid NOT NULL REFERENCES textbook_sections(id),
    activity_type text NOT NULL CHECK(activity_type IN ('new','review','assessment')),
    completed_work_units integer NOT NULL DEFAULT 0 CHECK(completed_work_units >= 0),
    spent_minutes integer NOT NULL CHECK(spent_minutes > 0),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    note text,
    CHECK(activity_type = 'new' OR completed_work_units = 0)
);

-- One observation can be an aggregate of multiple questions tied to the same skill.
CREATE TABLE skill_assessments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES students(id),
    skill_id uuid NOT NULL REFERENCES skills(id),
    lesson_id uuid REFERENCES lesson_sessions(id),
    section_id uuid REFERENCES textbook_sections(id),
    observed_at timestamptz NOT NULL DEFAULT now(),
    source text NOT NULL CHECK(source IN ('diagnostic','quiz','homework','exam')),
    difficulty text NOT NULL DEFAULT 'standard' CHECK(difficulty IN ('basic','standard','advanced')),
    attempted integer NOT NULL CHECK(attempted > 0),
    correct integer NOT NULL CHECK(correct >= 0 AND correct <= attempted),
    time_minutes numeric(8,2) CHECK(time_minutes IS NULL OR time_minutes >= 0),
    error_reason text CHECK(error_reason IN ('concept','procedure','careless','time','mixed','unknown')),
    note text
);

-- This is an evidence-based heuristic score initially, NOT a validated probability.
CREATE TABLE student_skill_states (
    student_id uuid NOT NULL REFERENCES students(id),
    skill_id uuid NOT NULL REFERENCES skills(id),
    readiness_score numeric(4,3) NOT NULL CHECK(readiness_score BETWEEN 0 AND 1),
    evidence_questions integer NOT NULL DEFAULT 0 CHECK(evidence_questions >= 0),
    confidence text NOT NULL DEFAULT 'low' CHECK(confidence IN ('low','medium','high')),
    algorithm_version text NOT NULL,
    calculated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(student_id, skill_id)
);

-- Versioned planning snapshots: approved runs should be treated as immutable.
CREATE TABLE plan_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES students(id),
    goal_id uuid NOT NULL REFERENCES learning_goals(id),
    supersedes_run_id uuid REFERENCES plan_runs(id),
    generated_by uuid REFERENCES teachers(id),
    status text NOT NULL DEFAULT 'draft'
        CHECK(status IN ('draft','approved','superseded','rejected')),
    created_at timestamptz NOT NULL DEFAULT now(),
    approved_at timestamptz,
    horizon_start date NOT NULL,
    horizon_end date NOT NULL,
    algorithm_version text NOT NULL,
    data_cutoff_at timestamptz NOT NULL,
    available_minutes integer NOT NULL CHECK(available_minutes >= 0),
    needed_minutes integer NOT NULL CHECK(needed_minutes >= 0),
    reserve_minutes integer NOT NULL DEFAULT 0 CHECK(reserve_minutes >= 0),
    shortfall_minutes integer NOT NULL DEFAULT 0 CHECK(shortfall_minutes >= 0),
    summary_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    CHECK(horizon_end >= horizon_start)
);

CREATE TABLE plan_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id uuid NOT NULL REFERENCES plan_runs(id),
    lesson_id uuid NOT NULL REFERENCES lesson_sessions(id),
    section_id uuid NOT NULL REFERENCES textbook_sections(id),
    activity_type text NOT NULL CHECK(activity_type IN ('new','review','assessment')),
    item_order integer NOT NULL CHECK(item_order > 0),
    allocated_minutes integer NOT NULL CHECK(allocated_minutes > 0),
    planned_work_units integer NOT NULL DEFAULT 0 CHECK(planned_work_units >= 0),
    teacher_locked boolean NOT NULL DEFAULT false,
    reason_code text NOT NULL,
    note text,
    UNIQUE(run_id, lesson_id, item_order),
    CHECK(activity_type = 'new' OR planned_work_units = 0)
);

CREATE TABLE plan_audit_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id uuid NOT NULL REFERENCES plan_runs(id),
    actor_teacher_id uuid REFERENCES teachers(id),
    action text NOT NULL CHECK(action IN ('created','edited','approved','rejected','superseded')),
    change_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Read model: coverage is NOT the same as verified skill mastery.
CREATE VIEW v_student_section_progress AS
SELECT st.student_id, sec.id AS section_id,
       sec.work_units_total,
       LEAST(sec.work_units_total,
             COALESCE(b.completed_work_units, 0) + COALESCE(a.completed_work_units, 0)
       ) AS completed_work_units,
       GREATEST(0, sec.work_units_total -
             COALESCE(b.completed_work_units, 0) - COALESCE(a.completed_work_units, 0)
       ) AS remaining_work_units
FROM student_textbooks st
JOIN textbook_sections sec ON sec.textbook_id = st.textbook_id
LEFT JOIN student_section_progress_baselines b
    ON b.student_id = st.student_id AND b.section_id = sec.id
LEFT JOIN (
    SELECT sess.student_id, act.section_id,
           SUM(act.completed_work_units) AS completed_work_units
    FROM lesson_activities act
    JOIN lesson_sessions sess ON sess.id = act.lesson_id
    WHERE act.activity_type = 'new'
    GROUP BY sess.student_id, act.section_id
) a ON a.student_id = st.student_id AND a.section_id = sec.id;

CREATE INDEX idx_students_academy ON students(academy_id);
CREATE INDEX idx_student_sessions ON lesson_sessions(student_id, starts_at);
CREATE INDEX idx_goal_student_due ON learning_goals(student_id, due_on);
CREATE INDEX idx_assessments_student_skill_time ON skill_assessments(student_id, skill_id, observed_at DESC);
CREATE INDEX idx_lesson_activities_lesson ON lesson_activities(lesson_id);
CREATE INDEX idx_lesson_activities_section ON lesson_activities(section_id);
CREATE INDEX idx_plan_runs_student_time ON plan_runs(student_id, created_at DESC);
CREATE INDEX idx_plan_items_run_lesson ON plan_items(run_id, lesson_id);
CREATE INDEX idx_goal_sections_section ON goal_sections(section_id);
CREATE INDEX idx_section_skills_skill ON section_skills(skill_id);

COMMIT;
