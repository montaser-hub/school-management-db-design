# School Management System — Database Design

A complete database design for a multi-branch school: from the conceptual ER model, through the relational mapping, to a **PostgreSQL schema that is tested against a real database**.

It covers users and roles, the school → branch → class → subject structure, schedules and attendance, exams and quizzes, reports, announcements and notifications, multi-step leave approvals, configurable schedule swaps, and audit logging.

| | |
| --- | --- |
| **Entities** | 21 (13 strong, 8 weak) |
| **Relations in the mapping** | 60 |
| **Tables in the SQL schema** | 59, with 110 foreign keys |
| **Verified by** | 17 constraint tests and 8 example queries on PostgreSQL 16 |

![User and role relationships](diagrams/02-relations-user-role.webp)

## Contents

- [Design process](#design-process)
- [The diagrams](#the-diagrams)
- [Core structure at a glance](#core-structure-at-a-glance)
- [Try it](#try-it)
- [Example queries](#example-queries)
- [Design decisions](#design-decisions)
- [Design review: what changed between the mapping and the SQL](#design-review-what-changed-between-the-mapping-and-the-sql)
- [Repository layout](#repository-layout)

## Design process

1. **Conceptual model.** Identify the entities and their attributes ([entities diagram](diagrams/01-entities.webp)), marking keys, multi-valued, composite and derived attributes, and which entities are weak (they cannot exist without an owner).
2. **Relationships.** Draw every relationship with its cardinality and participation. There are too many for one readable diagram, so they are split by area into four.
3. **Relational mapping.** Convert the ER model into relations: one per entity, one per many-to-many relationship, one per multi-valued attribute, with foreign keys for one-to-many relationships. This gives the [60 relations](docs/relational-mapping.md).
4. **Physical schema.** Implement the mapping in PostgreSQL with types, constraints, indexes and triggers: [`sql/schema.sql`](sql/schema.sql).
5. **Verification.** Load sample data, run real queries, and test that invalid data is rejected: [`sql/tests.sql`](sql/tests.sql).

### Notation used in the diagrams

| Element | Drawn as |
| --- | --- |
| Strong entity | Filled rounded box |
| Weak entity | Rounded box with an outline |
| Attribute | Ellipse |
| Key attribute | Underlined |
| Multi-valued attribute | Double ellipse |
| Composite attribute | Ellipse with child ellipses |
| Derived attribute | Dashed ellipse |
| Relationship | Diamond, labelled with its cardinality (`1:1`, `1:M`, `M:N`) |
| Total participation ("must") | Line ending in a dot |
| Partial participation ("may") | Plain line |

## The diagrams

| Diagram | What it shows |
| --- | --- |
| [Entities](diagrams/01-entities.webp) | All 21 entities with their attributes |
| [User and role relationships](diagrams/02-relations-user-role.webp) | How users relate to everything else: roles, branches, classes, schedules, requests |
| [School and branch relationships](diagrams/03-relations-school-branch.webp) | What each branch owns: classes, subjects, exams, quizzes, schedules, reports |
| [Class, subject, leave and swap relationships](diagrams/04-relations-class-subject-leave-swap.webp) | Academic structure plus the two request workflows |
| [Exam, quiz, schedule, report and result relationships](diagrams/05-relations-exam-quiz-report.webp) | Assessment and reporting |
| [Relational mapping](diagrams/06-relational-mapping.webp) | The 60 relations ([as searchable text](docs/relational-mapping.md)) |

<details>
<summary>Entities diagram</summary>

![Entities](diagrams/01-entities.webp)

</details>

<details>
<summary>School and branch relationships</summary>

![School and branch relationships](diagrams/03-relations-school-branch.webp)

</details>

<details>
<summary>Class, subject, leave and swap relationships</summary>

![Class, subject, leave and swap relationships](diagrams/04-relations-class-subject-leave-swap.webp)

</details>

<details>
<summary>Exam, quiz, schedule, report and result relationships</summary>

![Exam, quiz, schedule, report and result relationships](diagrams/05-relations-exam-quiz-report.webp)

</details>

## Core structure at a glance

The central tables of the implemented schema (junction tables and most attributes omitted):

```mermaid
erDiagram
    schools ||--|{ branches : has
    branches ||--o{ users : "home branch of"
    users ||--o{ users : supervises
    users }o--o{ roles : "user_roles"
    branches }o--o{ classes : "branch_classes"
    branches }o--o{ subjects : "branch_subjects"
    classes }o--o{ subjects : "class_subjects"
    classes }o--|| schedules : "runs on"
    users }o--o{ classes : "user_classes"
    users }o--o{ schedules : "user_schedules"
    subjects ||--o{ exams : has
    subjects ||--o{ quizzes : has
    exams ||--o{ exam_results : graded
    users ||--o{ exam_results : sits
    schedules ||--o{ attendance : "session per day"
    attendance ||--o{ user_attendance : records
    users ||--o{ leave_requests : submits
    leave_requests ||--|{ leave_request_approvals : "approval chain"
    users ||--o{ swap_requests : submits
    swap_configs ||--o{ swap_requests : governs
    reports ||--o{ results : contains
```

## Try it

Requirements: Docker.

```bash
git clone https://github.com/montaser-hub/school-management-db-design.git
cd school-management-db-design
docker compose up -d          # PostgreSQL 16 with the schema and sample data loaded

# run the example queries
docker compose exec db psql -U school -d school -f /sql/queries.sql

# run the constraint tests (rolled back afterwards)
docker compose exec db psql -U school -d school -v ON_ERROR_STOP=1 -f /sql/tests.sql
```

To connect with your own client: `postgresql://school:school@localhost:5433/school`.

Without Docker, run `sql/schema.sql` and then `sql/sample-data.sql` against any PostgreSQL 14+ database.

## Example queries

[`sql/queries.sql`](sql/queries.sql) answers eight questions the system needs to answer. Two of them:

**Exam results, keeping only each student's latest attempt**

```sql
SELECT e.title, u.first_name || ' ' || u.last_name AS student,
       r.attempt_number,
       CASE WHEN r.is_absent THEN 'absent' ELSE r.marks::text END AS marks
FROM exams e
JOIN LATERAL (
    SELECT DISTINCT ON (user_id) *
    FROM exam_results
    WHERE exam_id = e.id
    ORDER BY user_id, attempt_number DESC
) r ON true
JOIN users u ON u.id = r.user_id
ORDER BY r.marks DESC NULLS LAST;
```

```
          title          |    student    | attempt_number | marks
-------------------------+---------------+----------------+--------
 Mathematics 9 — Midterm | Layla Ibrahim |              1 | 92.00
 Mathematics 9 — Midterm | Nadia Fouad   |              1 | 84.50
 Mathematics 9 — Midterm | Omar Sherif   |              2 | 71.00
 Mathematics 9 — Midterm | Youssef Adel  |              1 | absent
```

**Leave requests waiting on an approver** (shown here with a parameter). A request only reaches level 2 once level 1 has approved:

```sql
SELECT lr.id, requester.first_name || ' ' || requester.last_name AS requested_by,
       lt.name AS leave_type, a.approval_level
FROM leave_request_approvals a
JOIN leave_requests lr ON lr.id = a.leave_request_id
JOIN users requester   ON requester.id = lr.user_id
JOIN leave_types lt    ON lt.id = lr.leave_type_id
WHERE a.approver_id = :approver AND a.status = 'pending'
  AND NOT EXISTS (
      SELECT 1 FROM leave_request_approvals earlier
      WHERE earlier.leave_request_id = a.leave_request_id
        AND earlier.approval_level < a.approval_level
        AND earlier.status <> 'approved');
```

The others: a teacher's weekly timetable, class average and pass rate, attendance summary, who may approve a swap request, announcements visible to a user, and subjects blocked by an unmet prerequisite.

## Design decisions

- **School → Branch → Class/Subject.** Classes and subjects are defined once and attached to branches through junction tables, so two branches can offer the same subject without duplicating it.
- **One `users` table with roles**, instead of separate teacher and student tables. A person can hold several roles (a supervisor who also teaches), and roles carry permissions as data.
- **Schedules are reusable time slots** (start, end, days of the week) assigned to users, classes, exams and quizzes. That is what makes a schedule swap a simple exchange of two slot references.
- **Configurable swap rules.** `swap_configs` holds the policy (notice period, monthly limit, cross-branch or not), and separate tables record which roles may initiate and which may approve under each policy, so rules change without a schema change.
- **Multi-step leave approval.** Each leave request has an ordered chain of approvers (`approval_level`), each with its own status and timestamp.
- **Results allow resits.** `attempt_number` is part of the key of exam and quiz results.
- **Weak entities cascade.** Logs, leave requests, swap requests, results and attendance sessions are deleted with their owner; ordinary references (such as "created by") are set to null instead, so history survives when a user is removed.
- **Rules live in the database.** Check constraints reject impossible data (a schedule that ends before it starts, marks for an absent student, a user supervising themselves); a compound foreign key ensures a leave entitlement refers to a role the user actually holds; a partial unique index allows only one primary contact per branch.

## Design review: what changed between the mapping and the SQL

Implementing the mapping exposed places where it was inconsistent or incomplete. The SQL resolves each one:

| In the mapping | Problem | In the SQL |
| --- | --- | --- |
| `Address` is listed twice (#51 and #52) | Two relations with one name; city and state depend on the same key | One `addresses` table with `city` and `state` columns |
| `Exam(SubjectCode, ExamId)`, `Quiz(SubjectCode, QuizId)` | Composite keys, but `ExamResult`, `BranchExam` and others reference `ExamId` alone | `id` is the key; `subject_code` is a mandatory foreign key |
| `Branch(SchoolCode, BranchCode)` | Composite key, but eight relations reference `BranchCode` alone | `branch_code` is the key; `school_code` is a mandatory foreign key |
| `UserClass.ClassId`, `UserSubject.SubjectId`, `AnnouncementRole.RoleId`, `NotificationRole.RoleId`, `UserRoleLeaveType.RoleId` | The referenced keys are `ClassCode`, `SubjectCode` and `RoleCode` | Code columns used throughout |
| `ExamResult(UserId, ExamId, …, AttemptNumber)` | The key permits one row per student per exam, so a second attempt could not be stored | `attempt_number` is part of the key |
| `School` has no name | The ER entity has a `Name` attribute | `name` added |
| `School(SchoolCode, PrincipalName, WebsiteUrl)` all marked as key | A key should be minimal | `school_code` is the key; `website_url` is unique |
| `User.Age` | Derived attribute | Not stored; computed from `date_of_birth` |
| `IsEnables`, `RepoterId`, `AnnouncementBy` | Typos and an unclear name | `is_enabled`, `reporter_id`, `announcement_media` |
| Weak-entity keys such as `Log(UserId, LogId)` | Composite keys make every reference two columns wide | A single identity key plus a mandatory, cascading foreign key to the owner |
| `Announcement`, `Notification` and `SwapConf` drawn as weak entities | They should outlive the user who created them: deleting an administrator must not delete the school's swap policy or past announcements | Ordinary tables; `created_by` is set to null when the creator is removed |

The value sets for status-style columns (for example leave status: pending, approved, rejected, cancelled) are implementation choices; the ER model leaves them open.

## Repository layout

```
diagrams/                 ER diagrams and the relational mapping (WebP)
docs/relational-mapping.md  the 60 relations as text, with the table that implements each
sql/schema.sql            PostgreSQL schema: tables, constraints, indexes, triggers
sql/sample-data.sql       a small fictional school
sql/queries.sql           eight example queries
sql/tests.sql             17 constraint, cascade and trigger tests
docker-compose.yml        PostgreSQL with everything pre-loaded
```

## License

[MIT](LICENSE) © Montaser Ismail
