-- =============================================================================
-- School Management System — PostgreSQL schema
--
-- Physical implementation of the relational mapping in
-- diagrams/06-relational-mapping.webp (60 relations → 59 tables; the two
-- "Address" relations are merged). Where the SQL deviates from the mapping,
-- the reason is noted inline and summarised in the README.
--
-- Conventions
--   * snake_case, plural table names (avoids the reserved word "user")
--   * natural "code" keys where the design uses them (role, school, branch,
--     class, subject); identity columns elsewhere
--   * weak entities cascade on delete with their owner
--   * every table that has updated_at gets a trigger that maintains it
--
-- Tested on PostgreSQL 16.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Users and roles
-- ---------------------------------------------------------------------------

CREATE TABLE users (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email                  varchar(254) NOT NULL UNIQUE CHECK (email = lower(email)),
    first_name             varchar(60)  NOT NULL,
    last_name              varchar(60)  NOT NULL,
    date_of_birth          date,                        -- "Age" in the ER model is derived from this
    picture_url            text,
    gender                 varchar(10)  CHECK (gender IN ('male', 'female', 'other')),
    status                 varchar(10)  NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    supervisor_id          bigint REFERENCES users (id) ON DELETE SET NULL,
    branch_code            varchar(20),                 -- FK added after branches exists (circular reference)
    password_hash          text         NOT NULL,
    password_changed_at    timestamptz,
    password_reset_token   text,
    password_reset_expires timestamptz,
    created_at             timestamptz  NOT NULL DEFAULT now(),
    updated_at             timestamptz  NOT NULL DEFAULT now(),
    CHECK (supervisor_id IS NULL OR supervisor_id <> id)
);

-- Multi-valued attribute "Contact" of User
CREATE TABLE user_phones (
    user_id      bigint      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    contact_info varchar(30) NOT NULL,
    phone_type   varchar(20) NOT NULL DEFAULT 'mobile',
    PRIMARY KEY (user_id, contact_info)
);

CREATE TABLE roles (
    role_code       varchar(30) PRIMARY KEY,
    name            varchar(80) NOT NULL UNIQUE,
    is_global_admin boolean     NOT NULL DEFAULT false,
    description     text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Multi-valued attribute "Permissions" of Role
CREATE TABLE role_permissions (
    role_code       varchar(30) NOT NULL REFERENCES roles (role_code) ON UPDATE CASCADE ON DELETE CASCADE,
    permission_code varchar(60) NOT NULL,
    PRIMARY KEY (role_code, permission_code)
);

-- User M:N Role
CREATE TABLE user_roles (
    user_id    bigint      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role_code  varchar(30) NOT NULL REFERENCES roles (role_code) ON UPDATE CASCADE,
    start_date date        NOT NULL DEFAULT current_date,
    PRIMARY KEY (user_id, role_code)
);

-- ---------------------------------------------------------------------------
-- 2. Places: location (geo) and address (postal)
-- ---------------------------------------------------------------------------

CREATE TABLE locations (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    map_url           text,
    description       text,
    latitude          numeric(9, 6) NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude         numeric(9, 6) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    geofence_radius_m integer CHECK (geofence_radius_m > 0),
    created_by        bigint REFERENCES users (id) ON DELETE SET NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);

-- The mapping lists Address twice (#51 with street details, #52 with
-- Id/City/State). Both describe the same entity, so they are one table here.
CREATE TABLE addresses (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    country      varchar(60)  NOT NULL,
    state        varchar(60),
    city         varchar(60)  NOT NULL,
    street_name  varchar(120) NOT NULL,
    block_number varchar(20),
    zip_code     varchar(20),
    landmark     varchar(120),
    created_by   bigint REFERENCES users (id) ON DELETE SET NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 3. School and branches
-- ---------------------------------------------------------------------------

CREATE TABLE schools (
    school_code    varchar(20)  PRIMARY KEY,
    name           varchar(120) NOT NULL,              -- present on the ER entity, missing from the mapping
    principal_name varchar(120),
    website_url    text UNIQUE,
    logo_url       text,
    manager_id     bigint REFERENCES users (id) ON DELETE SET NULL,   -- User 1:1 manages School
    school_type    varchar(30),
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);

-- Multi-valued attribute "Founders" of School
CREATE TABLE school_founders (
    school_code varchar(20)  NOT NULL REFERENCES schools (school_code) ON UPDATE CASCADE ON DELETE CASCADE,
    founder     varchar(120) NOT NULL,
    start_date  date,
    PRIMARY KEY (school_code, founder)
);

-- The mapping keys Branch on (SchoolCode, BranchCode), but every table that
-- references a branch uses BranchCode alone, so branch_code is the key and
-- school_code a mandatory foreign key (School 1:M Branch, total participation).
CREATE TABLE branches (
    branch_code      varchar(20)  PRIMARY KEY,
    school_code      varchar(20)  NOT NULL REFERENCES schools (school_code) ON UPDATE CASCADE,
    branch_name      varchar(120) NOT NULL,
    is_active        boolean      NOT NULL DEFAULT true,
    branch_type      varchar(30),
    manager_id       bigint REFERENCES users (id) ON DELETE SET NULL,  -- User 1:1 manages Branch
    established_date date,
    address_id       bigint UNIQUE REFERENCES addresses (id),          -- Branch 1:1 Address
    location_id      bigint UNIQUE REFERENCES locations (id),          -- Branch 1:1 Location
    created_at       timestamptz  NOT NULL DEFAULT now(),
    updated_at       timestamptz  NOT NULL DEFAULT now()
);

-- Now that branches exists: User M:1 Branch
ALTER TABLE users
    ADD CONSTRAINT users_branch_code_fkey
    FOREIGN KEY (branch_code) REFERENCES branches (branch_code) ON UPDATE CASCADE ON DELETE SET NULL;

CREATE TABLE branch_emails (
    branch_code varchar(20)  NOT NULL REFERENCES branches (branch_code) ON UPDATE CASCADE ON DELETE CASCADE,
    email       varchar(254) NOT NULL CHECK (email = lower(email)),
    PRIMARY KEY (branch_code, email)
);

CREATE TABLE branch_contact_info (
    branch_code  varchar(20) NOT NULL REFERENCES branches (branch_code) ON UPDATE CASCADE ON DELETE CASCADE,
    contact_info varchar(60) NOT NULL,
    type         varchar(20) NOT NULL DEFAULT 'phone',
    is_primary   boolean     NOT NULL DEFAULT false,
    PRIMARY KEY (branch_code, contact_info)
);

-- At most one primary contact per branch
CREATE UNIQUE INDEX branch_contact_one_primary ON branch_contact_info (branch_code) WHERE is_primary;

-- ---------------------------------------------------------------------------
-- 4. Schedules
-- ---------------------------------------------------------------------------

CREATE TABLE schedules (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    start_time time NOT NULL,
    end_time   time NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (end_time > start_time)
);

-- Multi-valued attribute "Days Of The Week" of Schedule
CREATE TABLE schedule_days (
    schedule_id bigint      NOT NULL REFERENCES schedules (id) ON DELETE CASCADE,
    day_of_week varchar(9)  NOT NULL CHECK (day_of_week IN
        ('saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday')),
    PRIMARY KEY (schedule_id, day_of_week)
);

CREATE TABLE user_schedules (
    user_id       bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    schedule_id   bigint NOT NULL REFERENCES schedules (id) ON DELETE CASCADE,
    assigned_by   bigint REFERENCES users (id) ON DELETE SET NULL,
    date_assigned date   NOT NULL DEFAULT current_date,
    PRIMARY KEY (user_id, schedule_id)
);

CREATE TABLE branch_schedules (
    branch_code varchar(20) NOT NULL REFERENCES branches (branch_code) ON UPDATE CASCADE ON DELETE CASCADE,
    schedule_id bigint      NOT NULL REFERENCES schedules (id) ON DELETE CASCADE,
    added_by    bigint REFERENCES users (id) ON DELETE SET NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (branch_code, schedule_id)
);

-- ---------------------------------------------------------------------------
-- 5. Classes and subjects
-- ---------------------------------------------------------------------------

CREATE TABLE classes (
    class_code    varchar(20)  PRIMARY KEY,
    class_type    varchar(30),
    name          varchar(120) NOT NULL,
    notes         text,
    academic_year varchar(9)   NOT NULL,                -- e.g. 2026/2027
    section       varchar(10),
    grade_level   smallint,
    capacity      integer CHECK (capacity > 0),
    manager_id    bigint REFERENCES users (id) ON DELETE SET NULL,     -- User 1:M manages Class
    schedule_id   bigint REFERENCES schedules (id) ON DELETE SET NULL, -- Class M:1 Schedule
    created_at    timestamptz  NOT NULL DEFAULT now(),
    updated_at    timestamptz  NOT NULL DEFAULT now()
);

CREATE TABLE subjects (
    subject_code varchar(20)  PRIMARY KEY,
    subject_type varchar(30),
    name         varchar(120) NOT NULL,
    description  text,
    units        smallint CHECK (units > 0),            -- credit units
    created_at   timestamptz  NOT NULL DEFAULT now(),
    updated_at   timestamptz  NOT NULL DEFAULT now()
);

-- Multi-valued attribute "Pre-requisites" of Subject (self-referencing M:N)
CREATE TABLE subject_prerequisites (
    subject_code              varchar(20) NOT NULL REFERENCES subjects (subject_code) ON UPDATE CASCADE ON DELETE CASCADE,
    prerequisite_subject_code varchar(20) NOT NULL REFERENCES subjects (subject_code) ON UPDATE CASCADE ON DELETE CASCADE,
    PRIMARY KEY (subject_code, prerequisite_subject_code),
    CHECK (subject_code <> prerequisite_subject_code)
);

CREATE TABLE class_subjects (
    class_code    varchar(20) NOT NULL REFERENCES classes (class_code) ON UPDATE CASCADE ON DELETE CASCADE,
    subject_code  varchar(20) NOT NULL REFERENCES subjects (subject_code) ON UPDATE CASCADE ON DELETE CASCADE,
    academic_year varchar(9)  NOT NULL,
    PRIMARY KEY (class_code, subject_code)
);

CREATE TABLE branch_classes (
    branch_code varchar(20) NOT NULL REFERENCES branches (branch_code) ON UPDATE CASCADE ON DELETE CASCADE,
    class_code  varchar(20) NOT NULL REFERENCES classes (class_code) ON UPDATE CASCADE ON DELETE CASCADE,
    added_by    bigint REFERENCES users (id) ON DELETE SET NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (branch_code, class_code)
);

CREATE TABLE branch_subjects (
    branch_code  varchar(20) NOT NULL REFERENCES branches (branch_code) ON UPDATE CASCADE ON DELETE CASCADE,
    subject_code varchar(20) NOT NULL REFERENCES subjects (subject_code) ON UPDATE CASCADE ON DELETE CASCADE,
    added_by     bigint REFERENCES users (id) ON DELETE SET NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (branch_code, subject_code)
);

-- The mapping calls these columns ClassId / SubjectId; the referenced keys
-- are ClassCode / SubjectCode, so the code columns are used.
CREATE TABLE user_classes (
    user_id       bigint      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    class_code    varchar(20) NOT NULL REFERENCES classes (class_code) ON UPDATE CASCADE ON DELETE CASCADE,
    assigned_by   bigint REFERENCES users (id) ON DELETE SET NULL,
    date_assigned date        NOT NULL DEFAULT current_date,
    PRIMARY KEY (user_id, class_code)
);

CREATE TABLE user_subjects (
    user_id       bigint      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    subject_code  varchar(20) NOT NULL REFERENCES subjects (subject_code) ON UPDATE CASCADE ON DELETE CASCADE,
    assigned_by   bigint REFERENCES users (id) ON DELETE SET NULL,
    date_assigned date        NOT NULL DEFAULT current_date,
    PRIMARY KEY (user_id, subject_code)
);

-- ---------------------------------------------------------------------------
-- 6. Reports and results
-- ---------------------------------------------------------------------------

CREATE TABLE reports (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    relevant      varchar(30),                          -- what the report relates to (exam, quiz, class…)
    type          varchar(30),
    date          date         NOT NULL DEFAULT current_date,
    title         varchar(160) NOT NULL,
    content       text,
    created_by    bigint REFERENCES users (id) ON DELETE SET NULL,
    audience_type varchar(30),
    is_published  boolean      NOT NULL DEFAULT false,
    created_at    timestamptz  NOT NULL DEFAULT now(),
    updated_at    timestamptz  NOT NULL DEFAULT now()
);

-- Multi-valued attribute "By" of Report ("RepoterId" in the mapping is a typo)
CREATE TABLE report_creators (
    report_id   bigint NOT NULL REFERENCES reports (id) ON DELETE CASCADE,
    reporter_id bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role        varchar(30),
    PRIMARY KEY (report_id, reporter_id)
);

-- Weak entity of Report
CREATE TABLE results (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    report_id  bigint NOT NULL REFERENCES reports (id) ON DELETE CASCADE,
    marks      numeric(6, 2) CHECK (marks >= 0),
    remarks    text,
    status     varchar(20),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE user_reports (
    user_id   bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    report_id bigint NOT NULL REFERENCES reports (id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, report_id)
);

CREATE TABLE class_reports (
    class_code varchar(20) NOT NULL REFERENCES classes (class_code) ON UPDATE CASCADE ON DELETE CASCADE,
    report_id  bigint      NOT NULL REFERENCES reports (id) ON DELETE CASCADE,
    created_by bigint REFERENCES users (id) ON DELETE SET NULL,
    PRIMARY KEY (class_code, report_id)
);

-- ---------------------------------------------------------------------------
-- 7. Exams and quizzes
-- ---------------------------------------------------------------------------

-- The mapping keys Exam on (SubjectCode, ExamId), but ExamResult and
-- BranchExam reference ExamId alone. id is therefore the key and
-- subject_code a mandatory foreign key (Subject 1:M Exam). Same for Quiz.
CREATE TABLE exams (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subject_code     varchar(20)  NOT NULL REFERENCES subjects (subject_code) ON UPDATE CASCADE,
    type             varchar(30),                       -- midterm, final…
    duration_minutes integer CHECK (duration_minutes > 0),
    date             date         NOT NULL,
    title            varchar(160) NOT NULL,
    marks            numeric(6, 2) NOT NULL CHECK (marks > 0),          -- maximum marks
    report_id        bigint REFERENCES reports (id) ON DELETE SET NULL,
    created_by       bigint REFERENCES users (id) ON DELETE SET NULL,
    created_at       timestamptz  NOT NULL DEFAULT now(),
    updated_at       timestamptz  NOT NULL DEFAULT now()
);

CREATE TABLE exam_schedules (
    exam_id     bigint NOT NULL REFERENCES exams (id) ON DELETE CASCADE,
    schedule_id bigint NOT NULL REFERENCES schedules (id) ON DELETE CASCADE,
    PRIMARY KEY (exam_id, schedule_id)
);

CREATE TABLE exam_reports (
    exam_id   bigint NOT NULL REFERENCES exams (id) ON DELETE CASCADE,
    report_id bigint NOT NULL REFERENCES reports (id) ON DELETE CASCADE,
    PRIMARY KEY (exam_id, report_id)
);

CREATE TABLE branch_exams (
    branch_code varchar(20) NOT NULL REFERENCES branches (branch_code) ON UPDATE CASCADE ON DELETE CASCADE,
    exam_id     bigint      NOT NULL REFERENCES exams (id) ON DELETE CASCADE,
    added_by    bigint REFERENCES users (id) ON DELETE SET NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (branch_code, exam_id)
);

-- attempt_number is part of the key: the mapping's (userId, ExamId) key
-- would allow only one attempt, which contradicts having an attempt counter.
CREATE TABLE exam_results (
    user_id        bigint   NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    exam_id        bigint   NOT NULL REFERENCES exams (id) ON DELETE CASCADE,
    attempt_number smallint NOT NULL DEFAULT 1 CHECK (attempt_number > 0),
    marks          numeric(6, 2) CHECK (marks >= 0),
    status         varchar(20),
    feedback       text,
    is_absent      boolean  NOT NULL DEFAULT false,
    PRIMARY KEY (user_id, exam_id, attempt_number),
    CHECK (NOT is_absent OR marks IS NULL)              -- an absent student has no marks
);

CREATE TABLE quizzes (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subject_code     varchar(20)  NOT NULL REFERENCES subjects (subject_code) ON UPDATE CASCADE,
    duration_minutes integer CHECK (duration_minutes > 0),
    date             date         NOT NULL,
    title            varchar(160) NOT NULL,
    marks            numeric(6, 2) NOT NULL CHECK (marks > 0),
    report_id        bigint REFERENCES reports (id) ON DELETE SET NULL,
    created_by       bigint REFERENCES users (id) ON DELETE SET NULL,
    created_at       timestamptz  NOT NULL DEFAULT now(),
    updated_at       timestamptz  NOT NULL DEFAULT now()
);

CREATE TABLE quiz_schedules (
    quiz_id     bigint NOT NULL REFERENCES quizzes (id) ON DELETE CASCADE,
    schedule_id bigint NOT NULL REFERENCES schedules (id) ON DELETE CASCADE,
    PRIMARY KEY (quiz_id, schedule_id)
);

CREATE TABLE quiz_reports (
    quiz_id   bigint NOT NULL REFERENCES quizzes (id) ON DELETE CASCADE,
    report_id bigint NOT NULL REFERENCES reports (id) ON DELETE CASCADE,
    PRIMARY KEY (quiz_id, report_id)
);

CREATE TABLE branch_quizzes (
    branch_code varchar(20) NOT NULL REFERENCES branches (branch_code) ON UPDATE CASCADE ON DELETE CASCADE,
    quiz_id     bigint      NOT NULL REFERENCES quizzes (id) ON DELETE CASCADE,
    added_by    bigint REFERENCES users (id) ON DELETE SET NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (branch_code, quiz_id)
);

CREATE TABLE quiz_results (
    user_id        bigint   NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    quiz_id        bigint   NOT NULL REFERENCES quizzes (id) ON DELETE CASCADE,
    attempt_number smallint NOT NULL DEFAULT 1 CHECK (attempt_number > 0),
    marks          numeric(6, 2) CHECK (marks >= 0),
    status         varchar(20),
    feedback       text,
    is_absent      boolean  NOT NULL DEFAULT false,
    PRIMARY KEY (user_id, quiz_id, attempt_number),
    CHECK (NOT is_absent OR marks IS NULL)
);

-- ---------------------------------------------------------------------------
-- 8. Attendance
-- ---------------------------------------------------------------------------

-- Weak entity of Schedule: one attendance session per schedule per day
CREATE TABLE attendance (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schedule_id bigint NOT NULL REFERENCES schedules (id) ON DELETE CASCADE,
    date        date   NOT NULL,
    remarks     text,
    status      varchar(20) NOT NULL DEFAULT 'open',
    UNIQUE (schedule_id, date)
);

CREATE TABLE user_attendance (
    user_id       bigint      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    attendance_id bigint      NOT NULL REFERENCES attendance (id) ON DELETE CASCADE,
    remarks       text,
    status        varchar(10) NOT NULL CHECK (status IN ('present', 'absent', 'late', 'excused')),
    PRIMARY KEY (user_id, attendance_id)
);

-- ---------------------------------------------------------------------------
-- 9. Announcements and notifications
-- ---------------------------------------------------------------------------

CREATE TABLE announcements (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title        varchar(160) NOT NULL,
    publish_date timestamptz  NOT NULL DEFAULT now(),
    description  text,
    created_by   bigint REFERENCES users (id) ON DELETE SET NULL,
    created_at   timestamptz  NOT NULL DEFAULT now(),
    updated_at   timestamptz  NOT NULL DEFAULT now()
);

-- Multi-valued attribute "Target" of Announcement (which roles see it).
-- The mapping says RoleId; the role key is RoleCode.
CREATE TABLE announcement_roles (
    announcement_id bigint      NOT NULL REFERENCES announcements (id) ON DELETE CASCADE,
    role_code       varchar(30) NOT NULL REFERENCES roles (role_code) ON UPDATE CASCADE ON DELETE CASCADE,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (announcement_id, role_code)
);

-- Multi-valued attribute "Media" of Announcement ("AnnouncementBy" in the mapping)
CREATE TABLE announcement_media (
    announcement_id bigint NOT NULL REFERENCES announcements (id) ON DELETE CASCADE,
    media_url       text   NOT NULL,
    media_type      varchar(20),
    PRIMARY KEY (announcement_id, media_url)
);

CREATE TABLE branch_announcements (
    branch_code     varchar(20) NOT NULL REFERENCES branches (branch_code) ON UPDATE CASCADE ON DELETE CASCADE,
    announcement_id bigint      NOT NULL REFERENCES announcements (id) ON DELETE CASCADE,
    added_by        bigint REFERENCES users (id) ON DELETE SET NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (branch_code, announcement_id)
);

CREATE TABLE notifications (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date        timestamptz  NOT NULL DEFAULT now(),
    title       varchar(160) NOT NULL,
    created_by  bigint REFERENCES users (id) ON DELETE SET NULL,
    description text,
    content     text,
    priority    varchar(10)  NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high')),
    created_at  timestamptz  NOT NULL DEFAULT now(),
    updated_at  timestamptz  NOT NULL DEFAULT now()
);

CREATE TABLE notification_roles (
    notification_id bigint      NOT NULL REFERENCES notifications (id) ON DELETE CASCADE,
    role_code       varchar(30) NOT NULL REFERENCES roles (role_code) ON UPDATE CASCADE ON DELETE CASCADE,
    PRIMARY KEY (notification_id, role_code)
);

CREATE TABLE user_notifications (
    user_id         bigint  NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    notification_id bigint  NOT NULL REFERENCES notifications (id) ON DELETE CASCADE,
    is_read         boolean NOT NULL DEFAULT false,
    PRIMARY KEY (user_id, notification_id)
);

-- ---------------------------------------------------------------------------
-- 10. Audit log
-- ---------------------------------------------------------------------------

-- Weak entity of User
CREATE TABLE logs (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    session_id  varchar(64),
    ip_address  inet,
    description text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Multi-valued attribute "Action" of Log ("UserLogAction" in the mapping)
CREATE TABLE log_actions (
    log_id bigint       NOT NULL REFERENCES logs (id) ON DELETE CASCADE,
    action varchar(120) NOT NULL,
    PRIMARY KEY (log_id, action)
);

-- ---------------------------------------------------------------------------
-- 11. Leave management
-- ---------------------------------------------------------------------------

CREATE TABLE leave_types (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        varchar(60) NOT NULL UNIQUE,
    type        varchar(30),                            -- paid, unpaid…
    description text,
    max_days    integer CHECK (max_days > 0)
);

-- Which leave types a user may take under each of their roles. The compound
-- foreign key guarantees the user actually holds that role.
CREATE TABLE user_role_leave_types (
    user_id       bigint      NOT NULL,
    role_code     varchar(30) NOT NULL,
    leave_type_id bigint      NOT NULL REFERENCES leave_types (id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_code, leave_type_id),
    FOREIGN KEY (user_id, role_code) REFERENCES user_roles (user_id, role_code) ON UPDATE CASCADE ON DELETE CASCADE
);

-- Weak entity of User
CREATE TABLE leave_requests (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    reason        text,
    start_date    date   NOT NULL,
    end_date      date   NOT NULL,
    leave_type_id bigint NOT NULL REFERENCES leave_types (id),
    status        varchar(10) NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CHECK (end_date >= start_date)
);

-- Multi-step approval chain: one row per approver, ordered by approval_level
CREATE TABLE leave_request_approvals (
    leave_request_id   bigint   NOT NULL REFERENCES leave_requests (id) ON DELETE CASCADE,
    approver_id        bigint   NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    status             varchar(10) NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending', 'approved', 'rejected')),
    approval_level     smallint NOT NULL DEFAULT 1 CHECK (approval_level > 0),
    remarks            text,
    approval_timestamp timestamptz,
    PRIMARY KEY (leave_request_id, approver_id),
    UNIQUE (leave_request_id, approval_level)
);

-- ---------------------------------------------------------------------------
-- 12. Schedule swaps
-- ---------------------------------------------------------------------------

-- "IsEnables" in the mapping is a typo for is_enabled
CREATE TABLE swap_configs (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    swap_type           varchar(30) NOT NULL,
    is_enabled          boolean     NOT NULL DEFAULT true,
    allow_cross_branch  boolean     NOT NULL DEFAULT false,
    max_swaps_per_month integer CHECK (max_swaps_per_month >= 0),
    min_notice_hours    integer CHECK (min_notice_hours >= 0),
    created_by          bigint REFERENCES users (id) ON DELETE SET NULL
);

-- Multi-valued attribute "Approver roles" of SwapConfig
CREATE TABLE swap_config_approver_roles (
    swap_config_id bigint      NOT NULL REFERENCES swap_configs (id) ON DELETE CASCADE,
    approval_role  varchar(30) NOT NULL REFERENCES roles (role_code) ON UPDATE CASCADE ON DELETE CASCADE,
    created_by     bigint REFERENCES users (id) ON DELETE SET NULL,
    PRIMARY KEY (swap_config_id, approval_role)
);

-- Role M:N SwapConfig: what each role may do under a configuration
CREATE TABLE role_swap_configs (
    role_code      varchar(30) NOT NULL REFERENCES roles (role_code) ON UPDATE CASCADE ON DELETE CASCADE,
    swap_config_id bigint      NOT NULL REFERENCES swap_configs (id) ON DELETE CASCADE,
    can_approve    boolean     NOT NULL DEFAULT false,
    can_initiate   boolean     NOT NULL DEFAULT false,
    PRIMARY KEY (role_code, swap_config_id)
);

-- Weak entity of User
CREATE TABLE swap_requests (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id               bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    reason                text,
    original_schedule_id  bigint NOT NULL REFERENCES schedules (id),
    requested_schedule_id bigint NOT NULL REFERENCES schedules (id),
    created_by            bigint REFERENCES users (id) ON DELETE SET NULL,
    swap_config_id        bigint NOT NULL REFERENCES swap_configs (id),
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CHECK (original_schedule_id <> requested_schedule_id)
);

CREATE TABLE swap_approvals (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    swap_request_id bigint NOT NULL REFERENCES swap_requests (id) ON DELETE CASCADE,
    approver_id     bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    status          varchar(10) NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'approved', 'rejected')),
    note            text,
    UNIQUE (swap_request_id, approver_id)
);

-- ---------------------------------------------------------------------------
-- 13. Indexes on foreign keys used by common lookups
--     (primary keys and UNIQUE constraints are indexed automatically)
-- ---------------------------------------------------------------------------

CREATE INDEX users_branch_code_idx           ON users (branch_code);
CREATE INDEX users_supervisor_id_idx         ON users (supervisor_id);
CREATE INDEX user_roles_role_code_idx        ON user_roles (role_code);
CREATE INDEX branches_school_code_idx        ON branches (school_code);
CREATE INDEX classes_schedule_id_idx         ON classes (schedule_id);
CREATE INDEX classes_manager_id_idx          ON classes (manager_id);
CREATE INDEX user_classes_class_code_idx     ON user_classes (class_code);
CREATE INDEX user_subjects_subject_code_idx  ON user_subjects (subject_code);
CREATE INDEX user_schedules_schedule_id_idx  ON user_schedules (schedule_id);
CREATE INDEX exams_subject_code_idx          ON exams (subject_code);
CREATE INDEX exam_results_exam_id_idx        ON exam_results (exam_id);
CREATE INDEX quizzes_subject_code_idx        ON quizzes (subject_code);
CREATE INDEX quiz_results_quiz_id_idx        ON quiz_results (quiz_id);
CREATE INDEX results_report_id_idx           ON results (report_id);
CREATE INDEX user_attendance_attendance_idx  ON user_attendance (attendance_id);
CREATE INDEX logs_user_id_created_at_idx     ON logs (user_id, created_at DESC);
CREATE INDEX leave_requests_user_id_idx      ON leave_requests (user_id);
CREATE INDEX leave_requests_pending_idx      ON leave_requests (status) WHERE status = 'pending';
CREATE INDEX leave_approvals_approver_idx    ON leave_request_approvals (approver_id);
CREATE INDEX swap_requests_user_id_idx       ON swap_requests (user_id);
CREATE INDEX user_notifications_unread_idx   ON user_notifications (user_id) WHERE NOT is_read;

-- ---------------------------------------------------------------------------
-- 14. Keep updated_at current on every table that has it
-- ---------------------------------------------------------------------------

CREATE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DO $$
DECLARE
    t text;
BEGIN
    FOR t IN
        SELECT table_name
        FROM information_schema.columns
        WHERE table_schema = current_schema() AND column_name = 'updated_at'
    LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
            t || '_set_updated_at', t
        );
    END LOOP;
END;
$$;

COMMIT;
