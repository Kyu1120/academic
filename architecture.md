# 통합형 수학 진도 계획 AI — 개발 설계서 (v0.1)

## 1. 목적 및 범위

개별 학생의 교재 완료일 또는 시험 대비 목표일을 입력받고, 학생의 현재 진도·수업시간·단원별 이해도·과거 학습속도를 종합하여 수업별 학습 계획을 생성한다. 수업과 평가가 완료될 때마다 계획을 다시 계산하되, 담당 교사가 검토·승인하기 전에는 공개된 수업 계획을 변경하지 않는다.

**최우선 성공 조건:** 제약 위반 없이 목표 달성 가능성/부족 시간을 명확히 보여준다. 목표일 준수가 불가능하다면 불가능하다고 반환한다.

**초기 제외:** 대규모 언어모델 신규 학습, 학생 자율 AI 튜터, 문제 이미지 인식/자동 채점, 전국 단위 교재 데이터 자동 수집, 학부모 포털. 향후 분리해서 확장한다.

## 2. 권장 기술 스택

- 교사 UI: Streamlit(빠른 시험) → React/Next.js(멀티유저 정식 서비스)
- API/인증: Python 3.12+, FastAPI, Pydantic/SQLModel 또는 SQLAlchemy/Alembic, 인증 제공자(OIDC)
- 데이터베이스: PostgreSQL 15+; 교사별 학습 데이터 접근 통제
- 계획 계산: 우선 순위/선수학습 기반 결정론적 휴리스틱 → 복잡해지면 OR-Tools CP-SAT
- 학습 속도 예측: pandas/scikit-learn, 초기에는 조정 가능한 규칙 기반 중앙값 추정
- 설명 문구: LLM(선택). 학생 실명/연락처 등은 프롬프트에서 제외하고 계산은 서버가 수행
- 테스트: pytest, 마이그레이션 CI, 시간대/동시성/교차 사용자 접근 검증

## 3. 핵심 도메인 모델

**학생/학원:** `academies`, `teachers`, `students`, `teacher_student_assignments`

**교재/교육과정:** `textbooks`, `textbook_sections`, `skills`, `skill_prerequisites`, `section_skills`, `student_textbooks`

**초기 진도/스케줄:** `student_section_progress_baselines`, `weekly_schedules`, `lesson_sessions`

**목표:** `learning_goals`, `goal_sections`

**학습 관찰:** `lesson_activities`, `skill_assessments`, `student_skill_states`

**AI 계획/승인/감사:** `plan_runs`, `plan_items`, `plan_audit_events`

**파생 뷰:** `v_student_section_progress` (단원 진도 완료량 = 초기 수기 진도 + 이후 신규학습 완료량; 최고값은 단원 분량으로 제한)

### 데이터 관계

- 학생 1명 → 여러 교재·수업 일정·학습 목표·진도 계획
- 교재 1권 → 여러 세부 단원 (진도 계획의 최소 단위)
- 세부 단원 ↔ 개념/스킬 N:M (교재별 목차와 교육과정 개념 구분)
- 스킬 ↔ 선수 스킬 N:M (선수 학습의 유향 비순환 그래프; 서비스에서 cycle 금지)
- 학생+스킬 → 여러 평가 기록 및 현재 준비도 스냅샷
- 목표 1개 → 목표 범위의 세부 단원 여러 개
- 계획 실행(run) 1개 → 여러 수업별 계획 항목(item); 새로운 실행은 기존 실행의 이전 버전을 참조

### 핵심 수집 필드(교사 입력)

| 입력 영역 | 필수 입력 | 있으면 좋은 입력 |
|---|---|---|
| 학생 | 학생코드, 학년 | 담당 교사 |
| 교재 | 제목, 개정/판본, 단원명·순서, 단원별 분량 | 예상 소요 시간, 관련 수학 개념 |
| 목표 | 완료 목표일, 목표 범위(세부 단원 목록) | 우선순위, 준비도 기준 |
| 수업 | 정확한 수업 날짜·시간, 실제 투입 가능 시간 | 정기 요일·결석·휴강 |
| 실제 진도 | 해당 수업 단원, 신규 진도 완료량, 실제 소요 시간 | 복습/평가 시간, 교사 메모 |
| 평가 | 평가 날짜, 개념 ID, 문항 수, 정답 수 | 난이도, 시간, 오답 원인 |

**주의:** 문항별 개념 매핑이 없다면 단원별 정답률만으로 개별 개념 숙련도를 정확하게 추정할 수 없다. 최소한 문제 묶음마다 평가 대상 스킬을 태깅한다.

## 4. 처리 파이프라인

### 4.1 교재 분량과 개념 이해도는 별도 측정

- `coverage = completed_work_units / work_units_total`은 학습 진도(분량) 지표
- `readiness_score ∈ [0,1]`은 관측된 정답률·난이도·최신성을 결합한 **휴리스틱 준비도 점수**. 신뢰할 만한 확률로 해석하거나 진짜 이해도를 보장한다고 표현하지 않는다.
- 평가 문항이 적으면 `confidence=low` 표시하고 **진단평가 우선 배정**
- 목표를 완성으로 판단할 때는 교재 분량 완료와 주요 개념의 충분한 평가 근거를 동시에 요구한다. 증거가 부족하면 '미판정'.

### 4.2 남은 시간 계산

단원 s의 예상 신규학습 시간(분):

`new_minutes(s) = round(baseline_minutes(s) × remaining_units(s)/total_units(s) × speed_factor(student, s))`

- 초기 `speed_factor=1.0` (교재 기준예상치를 그대로 사용)
- 기록이 일정량 누적되면 유사 단원/난이도에서 `실제 분/완료단위`를 추정. 극단치를 클리핑하고 신뢰구간·샘플수를 함께 표시
- 보충시간은 별도: 충분한 평가 근거가 있을 때 준비도가 기준보다 낮은 개념에 복습+재평가 시간을 추가
- 시험 전 모의평가나 최종 점검 시간도 별도 항목
- `needed_minutes = sum(new_minutes) + sum(review_minutes) + assessment_minutes`
- `usable_minutes = sum(future_session.available_minutes) - reserve_minutes`
- `shortfall_minutes = max(0, needed_minutes - usable_minutes)`

**초기 경험적 기본값(가설, 학원 데이터로 보정 필요):**
- 예비시간 10% (실제 수업 가능 시간의 10%, 원 단위 반올림)
- 최근 5문항 미만의 개념 평가: 신뢰도 낮음으로 표시
- 평가 근거가 충분하고 준비도 점수 0.7 미만: 복습 후보
- 복습 후 재평가를 수행하기 전까지 '성취 확인'으로 승격하지 않음

### 4.3 계획 생성

1. 학생·목표·교재·수업 일정의 정합성 확인(다른 학원 데이터 접근 차단)
2. 현재 시점 기준 예정 수업만 추출하고 휴강/결석을 제외
3. 목표 단원별 미진도와 선수 개념 조건 계산
4. 숙련도가 낮거나 근거 부족한 스킬에 대한 복습/진단 작업 생성
5. 작업마다 예상 시간, 목표일, 우선순위, 선행관계를 부여
6. 빠른 버전: 선수관계/교재 순서/마감일 우선 순으로 수업 가용 분에 작업 할당
7. 제약 충돌 시 작업량 감소를 숨기지 말고 부족 분·미배정 작업을 반환
8. `plan_runs(draft)` + `plan_items` 생성, 근거 코드/알고리즘 버전/데이터 기준시각 저장
9. 교사가 수정/승인하면 `approved` 상태로 전환

### 4.4 자동 재계획

**발화 조건:** 실제 진도 입력, 새 평가 등록, 수업 취소, 새 수업 추가, 목표일·교재 범위 변경.

- 완료된 과거 수업은 절대 다시 배정하지 않는다.
- 교사가 고정한 수업 항목은 유지한다. 고정 때문에 목표가 불가능해지면 부족시간을 보고한다.
- 새로운 `plan_runs`를 이전 승인 계획의 후속 버전으로 만들고 **변경 사항만 비교 표시**
- 자동 생성은 가능하지만, **자동 공개/승인은 하지 않는다**
- 동일 데이터를 입력하면 동일 계획(결정론적 tie-break + 버전 고정)을 생성해야 한다.

### 4.5 계획 최적화: 필수 제약 vs 목적함수

**필수:** 수업 시간 합계 ≤ 수업의 실제 가용 시간, 휴강에는 할당하지 않음, 완료량≤남은 분량, 교사의 수동 고정 유지, 명시된 선수학습 이수 순서, 목표 범위 외 과도한 배정 금지.

**목표:** 마감 기한 초과 최소화, 우선순위 높은 단원 우선, 복습 기회 확보, 재계획 시 기존 일정 변경 최소화, 같은 날 과부하 최소화.

예: 목적 함수 = `100 × 마감 초과 분 + 10 × 준비도 부족 위험 + 3 × 기존 계획 변경 분`. 계수는 **설명용**이며 실제 운영 전에 교사 피드백으로 조정한다.

CP-SAT은 제약이 복잡해지고 여러 학생·강사 시간표까지 동시에 풀 때 도입. 단일 학생의 순차 교재 진도만 계산할 땐 휴리스틱으로도 충분하다.

## 5. 수치 예제(가상)

- 남은 수업: 3회 × 실제 가용시간 90분 = 270분
- 여유시간 10% = 27분 → 실제 배정 가능 243분
- 신규 단원 A = 110분, 신규 단원 B = 90분, 취약 개념 복습/재평가 = 60분
- 필요 시간 = 260분, **부족 17분**

시스템 출력: `목표일 기준 계획 위험 / 부족 17분` 및 `추가 수업 30분`, `목표일 연장`, `교사의 범위 조정` 중 대안 제시. **준비도 기준을 임의로 낮추지 않는다.**

## 6. 필수 API (초기 구현)

| Method/endpoint | 동작 |
|---|---|
| `POST /students` | 학생 생성 |
| `POST /textbooks` 및 `POST /textbooks/{id}/sections` | 교재/세부 단원 등록 |
| `POST /students/{id}/goals` | 목표 및 목표 단원 설정 |
| `POST /students/{id}/lessons` | 개별 수업 일정 확정 |
| `POST /lessons/{id}/activities` | 실제 수업 진도/투입 시간 등록 |
| `POST /students/{id}/assessments` | 개념별 평가 등록 |
| `POST /students/{id}/plans:generate` | 새 초안 생성·재계획 (idempotency key 권장) |
| `GET /students/{id}/plans/latest` | 추천 수업별 계획 보기 |
| `GET /plans/{run_id}/compare/{prior_run_id}` | 이전 계획과 변경점 비교 |
| `PATCH /plans/{run_id}/items/{item_id}` | 초안 수동 수정, 수정 사유 저장 |
| `POST /plans/{run_id}/approve` | 교사 승인, 기존 승인 버전은 superseded 처리 |
| `GET /students/{id}/dashboard` | 목표일, 현재 진도, 준비도, 부족 시간 |

**추천 핵심 요청 예시**

```json
{
  "student_id": "<student UUID>",
  "goal_id": "<goal UUID>",
  "as_of_date": "2026-10-16",
  "reserve_ratio": 0.10,
  "preserve_locked_items": true
}
```

**추천 핵심 응답 필드 예시**

```json
{
  "plan_run_id": "<plan UUID>",
  "status": "draft",
  "available_minutes": 270,
  "reserve_minutes": 27,
  "needed_minutes": 260,
  "shortfall_minutes": 17,
  "feasible_by_deadline": false,
  "warnings": ["INSUFFICIENT_CAPACITY"],
  "items": [
    {"lesson_id": "<lesson UUID>", "section_id": "<section UUID>", "activity_type": "new", "allocated_minutes": 60, "planned_work_units": 3, "reason_code": "GOAL_DEADLINE"}
  ]
}
```

> `available_minutes`는 예약 제외 전 합계이며 배정가능시간은 `available_minutes - reserve_minutes`. `items`는 출력 형식 예시이며 전체 계획이 아니다.

## 7. 개발 모듈 구조

```text
math-planner/
  backend/
    app/
      api/          # FastAPI routes / authz
      db/           # SQLAlchemy models + migrations
      domain/       # curriculum graph / typed events
      services/     # progress, assessment, readiness
      forecasting/  # speed estimation / uncertainty
      planner/      # task generation, constraints, solver
      reporting/    # explanation and teacher dashboard data
    tests/          # fixture-backed unit & integration tests
  frontend/         # Streamlit initially; React later
  data/             # textbook catalog import templates
  docs/
  schema.sql
```

## 8. 교사용 화면 설계

**학생 상세 화면**: 학년/현재 교재/목표일/수업 일정/남은 분량/최근 평가/기본 진도 표.

**AI 계획 생성 화면**: 범위, 목표 날짜, 총 필요시간, 가능시간, 부족시간, 수업별 교재 단원·계획 분량·복습 시간을 표시. 교사가 드래그 수정, 고정, 승인.

**수업 종료 기록 화면**: 현재 계획에서 실제 진행량·소요시간, 이해도 간이 평가(단원별 문항/정답)만 입력. 누락 데이터 요청.

**계획 변경 화면**: 이전 일정 대비 변경된 단원, 변경 전/후 시간, 변경 이유(예: `SLOWER_THAN_EXPECTED`, `LOW_MASTERY`, `SESSION_CANCELLED`)를 제공.

## 9. 검증 및 평가

### 핵심 지표

- **수업시간 제약 위반률**: 0% 목표 (알고리즘 무결성)
- **진도 완료 소요시간 오차**: MAE(분), WAPE(%), 학년/교재/숙련도 층별 구분
- **목표일까지 진도 완료율**: 승인 계획 대비 실제 달성 여부
- **교사 수정률**: 계획 항목 중 교사가 수정한 비율과 수정 이유
- **불필요한 변경량**: 재계획 시 미래 수업 중 변경된 비율
- **단원 성취도 변화**: 같은 난이도·같은 개념의 전후 평가로 별도 측정

### 반드시 테스트할 시나리오

1. 목표일 이전 가용 수업이 0회인 경우
2. 목표까지 200분 필요, 가능한 시간은 100분인 경우 (부족 100분)
3. 교재는 이미 끝났지만 평가 근거가 없는 경우 (준비도 미판정)
4. 충분한 문항에서 준비도가 낮은 개념이 확인된 경우 (복습+재평가 추가)
5. 한 수업 취소 후 재계획(과거 수업 불변)
6. 교사가 특정 수업을 고정한 뒤 재계획(고정 유지)
7. 두 교재의 세부 단원이 동일 스킬을 공유(중복 복습 최소화)
8. 선수 스킬 그래프에 순환이 있을 경우(입력 거절)
9. 타 학원/권한 없는 교사가 학생 데이터 조회 시(차단)
10. 동일 입력으로 두 번 생성(동일한 배정과 재현 가능한 결정 근거)

## 10. 단계별 로드맵

**Phase 1 — 1인 운영 MVP**
- 교재/세부 단원 관리, 학생 및 수업 일정, 목표일 등록
- 매 수업 실제 진도 입력, 역산 수업별 계획, 부족 시간 탐지
- 교사 확인/수정, PDF/시트 출력은 추후 옵션
- 학원 데이터 10~20명의 사례로 검증 (모델 학습에 충분하다는 의미 아님)

**Phase 2 — 적응형 학습 계획**
- 스킬별 평가와 불확실성 추적, 개념 선수 관계 도입
- 속도 중앙값의 신뢰도와 단원 유사성 도입, 복습·진단 작업
- 변경 전/후 비교 및 교사 검토 흐름

**Phase 3 — 운영 최적화/ML**
- 충분한 실측 데이터에서 교재별 학습시간 예측 모델 비교
- 성능의 시간순 홀드아웃 검증(동일 학생의 미래 기록 유출 방지)
- 다수 학생·강사·교실 동시 편성, CP-SAT
- 학부모 보고서 자동 생성 및 대시보드 고도화

## 11. 보안과 운영

- 학생 개인정보 최소 수집. 평가·진도 데이터도 엄격히 접근 통제
- 서버에서 학원/담당 교사 권한 확인; PostgreSQL RLS는 다중 학원 운영 시 추가 방어선으로 검토
- 승인된 진도 계획 수정 금지. 재계획은 별도 버전 + 감사 기록
- 데이터 전송/보관 암호화, 백업, 복구·삭제 정책, 접근 로그 구축
- 아동 개인정보 처리 시 해당 법령, 적절한 고지 및 동의 요건을 운영 전에 확인
- 외부 LLM에 보내는 데이터는 가명 ID + 집계 통계 + 이유 코드만 전달, 실명 및 불필요한 개인 정보는 제외
- 교재의 저작권 있는 문제 원문은 권리 없이 외부 모델 또는 데이터베이스에 일괄 복제하지 않는다

## 12. 중요한 구현 주의사항

- `schema.sql`은 테이블/검사 제약/인덱스/뷰를 제공한다. **교사 권한 검사, 그래프 순환 탐지, 이중진도 입력 방지, 학원 소속 일치, 수업 중복 검사, 계획 승인 트랜잭션 등은 별도 서비스 코드에서 구현**해야 한다.
- 기존 엑셀/구글시트에서 진도 데이터 이관 시 `student_section_progress_baselines`에 초기 완료 단위만 등록한다. 같은 이전 기록을 `lesson_activities`에 추가하면 중복 집계되므로 금지.
- 기존 숙제점수/태도점수/평균 오답률만으로 스킬별 준비도를 추정하지 않는다. 스킬 ID와 연결된 평가 근거가 필요하다.
- 신규 단원 소요시간의 `baseline_minutes`는 교사 추정값으로 출발하므로 절대적 정확도를 약속하지 않는다.

## 참고 공식 문서

- FastAPI SQL Databases: https://fastapi.tiangolo.com/tutorial/sql-databases/
- Google OR-Tools CP-SAT: https://developers.google.com/optimization/cp/cp_solver
- PostgreSQL RLS: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
