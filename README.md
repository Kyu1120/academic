# Integrated Math Progress Planner — Codex handoff package

This archive is an **implementation brief and database draft**, not a working app.

## Contents
- `CODEX_TASK.md` — the one-shot task to implement the first functional MVP
- `AGENTS.md` — persistent instructions Codex can read from the project folder
- `architecture.md` — detailed adaptive progress-planning design (Korean)
- `schema.sql` — PostgreSQL 15+ starter schema (21 tables + progress view)

## Use in Codex
1. Unzip this folder on your computer.
2. Open the unzipped folder as the project in Codex (or start Codex CLI in that folder).
3. Send this message:

   > `AGENTS.md`, `CODEX_TASK.md`, `architecture.md`, `schema.sql`을 읽고 `CODEX_TASK.md`의 Phase 1 MVP를 실제로 구현해 줘. 설계만 하지 말고 파일 생성·로컬 실행·자동 테스트까지 진행하고, 실행 방법 및 남은 문제를 README.md에 정리해 줘.

4. Once code is produced, follow the updated README for setup and local demo.

## Privacy/security
All test records must be fictional. The MVP may use simplified local-only access. Never expose it on the internet or load real student data without authentication, authorization, tenancy validation, and appropriate privacy controls.
