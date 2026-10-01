-- =============================================================================
-- Sample data: one school, two branches, a handful of fictional people.
-- Small on purpose — enough to run every query in queries.sql.
-- Load after schema.sql.
-- =============================================================================

BEGIN;

-- Roles and permissions -------------------------------------------------------
INSERT INTO roles (role_code, name, is_global_admin, description) VALUES
    ('ADMIN',      'Administrator', true,  'Full access across all branches'),
    ('SUPERVISOR', 'Supervisor',    false, 'Manages teachers and approves requests'),
    ('TEACHER',    'Teacher',       false, 'Teaches classes, records attendance and marks'),
    ('STUDENT',    'Student',       false, 'Attends classes and sits exams');

INSERT INTO role_permissions (role_code, permission_code) VALUES
    ('ADMIN', 'users.manage'), ('ADMIN', 'branches.manage'), ('ADMIN', 'swaps.configure'),
    ('SUPERVISOR', 'leave.approve'), ('SUPERVISOR', 'swaps.approve'), ('SUPERVISOR', 'reports.publish'),
    ('TEACHER', 'attendance.record'), ('TEACHER', 'marks.record'), ('TEACHER', 'swaps.request'),
    ('STUDENT', 'results.view');

-- Users (branch_code is set once the branches exist) --------------------------
INSERT INTO users (email, first_name, last_name, date_of_birth, gender, password_hash) VALUES
    ('amina.farid@nileacademy.example',   'Amina',  'Farid',   '1978-03-14', 'female', '$2b$12$sample.hash.not.a.real.password.000000000000000000001'),
    ('hassan.zaki@nileacademy.example',   'Hassan', 'Zaki',    '1982-11-02', 'male',   '$2b$12$sample.hash.not.a.real.password.000000000000000000002'),
    ('mona.saleh@nileacademy.example',    'Mona',   'Saleh',   '1990-06-21', 'female', '$2b$12$sample.hash.not.a.real.password.000000000000000000003'),
    ('tarek.nasser@nileacademy.example',  'Tarek',  'Nasser',  '1988-01-09', 'male',   '$2b$12$sample.hash.not.a.real.password.000000000000000000004'),
    ('layla.ibrahim@nileacademy.example', 'Layla',  'Ibrahim', '2010-09-05', 'female', '$2b$12$sample.hash.not.a.real.password.000000000000000000005'),
    ('omar.sherif@nileacademy.example',   'Omar',   'Sherif',  '2010-04-17', 'male',   '$2b$12$sample.hash.not.a.real.password.000000000000000000006'),
    ('nadia.fouad@nileacademy.example',   'Nadia',  'Fouad',   '2011-02-28', 'female', '$2b$12$sample.hash.not.a.real.password.000000000000000000007'),
    ('youssef.adel@nileacademy.example',  'Youssef','Adel',    '2010-12-11', 'male',   '$2b$12$sample.hash.not.a.real.password.000000000000000000008');

-- Ids below are looked up by email so the script does not depend on identity values.
CREATE TEMP TABLE u ON COMMIT DROP AS
    SELECT split_part(email, '.', 1) AS key, id FROM users;

INSERT INTO user_roles (user_id, role_code, start_date)
SELECT u.id, r.role_code, DATE '2024-09-01'
FROM (VALUES ('amina', 'ADMIN'), ('hassan', 'SUPERVISOR'), ('mona', 'TEACHER'), ('tarek', 'TEACHER'),
             ('layla', 'STUDENT'), ('omar', 'STUDENT'), ('nadia', 'STUDENT'), ('youssef', 'STUDENT')) AS r (key, role_code)
JOIN u USING (key);

INSERT INTO user_phones (user_id, contact_info, phone_type)
SELECT id, '+20 100 555 0101', 'mobile' FROM u WHERE key = 'mona';

-- Teachers report to the supervisor
UPDATE users SET supervisor_id = (SELECT id FROM u WHERE key = 'hassan')
WHERE id IN (SELECT id FROM u WHERE key IN ('mona', 'tarek'));

-- School, places and branches -------------------------------------------------
INSERT INTO schools (school_code, name, principal_name, website_url, school_type, manager_id)
VALUES ('NILE', 'Nile Academy', 'Dr. Amina Farid', 'https://nileacademy.example', 'private',
        (SELECT id FROM u WHERE key = 'amina'));

INSERT INTO school_founders (school_code, founder, start_date) VALUES
    ('NILE', 'Farid Family Foundation', '1996-09-01');

INSERT INTO addresses (country, state, city, street_name, block_number, zip_code, landmark) VALUES
    ('Egypt', 'Cairo',      'Maadi',      'Road 9',           '14', '11728', 'Near Maadi metro station'),
    ('Egypt', 'Alexandria', 'Smouha',     'Fawzy Moaz Street','7',  '21615', 'Opposite Green Plaza');

INSERT INTO locations (latitude, longitude, geofence_radius_m, description) VALUES
    (29.960200, 31.257500, 150, 'Maadi campus main gate'),
    (31.215600, 29.955300, 150, 'Smouha campus main gate');

INSERT INTO branches (branch_code, school_code, branch_name, branch_type, manager_id, established_date, address_id, location_id) VALUES
    ('NILE-MAADI',  'NILE', 'Maadi Campus',  'main', (SELECT id FROM u WHERE key = 'hassan'), '1996-09-01',
        (SELECT id FROM addresses WHERE city = 'Maadi'),  (SELECT id FROM locations WHERE description LIKE 'Maadi%')),
    ('NILE-SMOUHA', 'NILE', 'Smouha Campus', 'sub',  NULL,                                    '2012-09-01',
        (SELECT id FROM addresses WHERE city = 'Smouha'), (SELECT id FROM locations WHERE description LIKE 'Smouha%'));

INSERT INTO branch_emails (branch_code, email) VALUES
    ('NILE-MAADI', 'maadi@nileacademy.example'), ('NILE-SMOUHA', 'smouha@nileacademy.example');

INSERT INTO branch_contact_info (branch_code, contact_info, type, is_primary) VALUES
    ('NILE-MAADI', '+20 2 5550 1000', 'phone', true), ('NILE-MAADI', '+20 2 5550 1001', 'fax', false);

UPDATE users SET branch_code = 'NILE-MAADI';

-- Schedules ---------------------------------------------------------------------
INSERT INTO schedules (start_time, end_time) VALUES ('08:00', '09:30'), ('09:45', '11:15'), ('11:30', '13:00');

CREATE TEMP TABLE s ON COMMIT DROP AS
    SELECT row_number() OVER (ORDER BY start_time) AS slot, id FROM schedules;

INSERT INTO schedule_days (schedule_id, day_of_week)
SELECT s.id, d.day
FROM s JOIN (VALUES (1, 'sunday'), (1, 'tuesday'), (1, 'thursday'),
                    (2, 'sunday'), (2, 'tuesday'), (2, 'thursday'),
                    (3, 'monday'), (3, 'wednesday')) AS d (slot, day) USING (slot);

INSERT INTO branch_schedules (branch_code, schedule_id) SELECT 'NILE-MAADI', id FROM s;

-- Classes and subjects ----------------------------------------------------------
INSERT INTO subjects (subject_code, subject_type, name, units) VALUES
    ('MATH-9', 'core', 'Mathematics 9', 4),
    ('PHYS-9', 'core', 'Physics 9', 3),
    ('MATH-10', 'core', 'Mathematics 10', 4);

INSERT INTO subject_prerequisites (subject_code, prerequisite_subject_code) VALUES ('MATH-10', 'MATH-9');

INSERT INTO classes (class_code, class_type, name, academic_year, section, grade_level, capacity, manager_id, schedule_id) VALUES
    ('G9-A', 'regular', 'Grade 9 — Section A', '2026/2027', 'A', 9, 30,
        (SELECT id FROM u WHERE key = 'mona'), (SELECT id FROM s WHERE slot = 1));

INSERT INTO class_subjects (class_code, subject_code, academic_year) VALUES
    ('G9-A', 'MATH-9', '2026/2027'), ('G9-A', 'PHYS-9', '2026/2027');

INSERT INTO branch_classes (branch_code, class_code)   VALUES ('NILE-MAADI', 'G9-A');
INSERT INTO branch_subjects (branch_code, subject_code) VALUES ('NILE-MAADI', 'MATH-9'), ('NILE-MAADI', 'PHYS-9');

INSERT INTO user_classes (user_id, class_code, assigned_by)
SELECT id, 'G9-A', (SELECT id FROM u WHERE key = 'hassan')
FROM u WHERE key IN ('mona', 'tarek', 'layla', 'omar', 'nadia', 'youssef');

INSERT INTO user_subjects (user_id, subject_code, assigned_by)
SELECT u.id, t.subject_code, (SELECT id FROM u WHERE key = 'hassan')
FROM (VALUES ('mona', 'MATH-9'), ('tarek', 'PHYS-9')) AS t (key, subject_code) JOIN u USING (key);

INSERT INTO user_schedules (user_id, schedule_id, assigned_by)
SELECT u.id, s.id, (SELECT id FROM u WHERE key = 'hassan')
FROM (VALUES ('mona', 1), ('mona', 3), ('tarek', 2)) AS t (key, slot) JOIN u USING (key) JOIN s USING (slot);

-- Exam, quiz and results ----------------------------------------------------------
INSERT INTO exams (subject_code, type, duration_minutes, date, title, marks, created_by) VALUES
    ('MATH-9', 'midterm', 90, '2026-11-15', 'Mathematics 9 — Midterm', 100, (SELECT id FROM u WHERE key = 'mona'));

INSERT INTO branch_exams (branch_code, exam_id) SELECT 'NILE-MAADI', id FROM exams;
INSERT INTO exam_schedules (exam_id, schedule_id) SELECT e.id, s.id FROM exams e, s WHERE s.slot = 1;

INSERT INTO exam_results (user_id, exam_id, attempt_number, marks, status, feedback, is_absent)
SELECT u.id, e.id, r.attempt, r.marks, r.status, r.feedback, r.absent
FROM exams e,
     (VALUES ('layla',   1, 92.0, 'passed', 'Excellent work',             false),
             ('omar',    1, 48.0, 'failed', 'Review algebra chapters',    false),
             ('omar',    2, 71.0, 'passed', 'Much improved on the resit', false),
             ('nadia',   1, 84.5, 'passed', NULL,                         false),
             ('youssef', 1, NULL, 'absent', 'Medical leave',              true)) AS r (key, attempt, marks, status, feedback, absent)
JOIN u USING (key);

INSERT INTO quizzes (subject_code, duration_minutes, date, title, marks, created_by) VALUES
    ('PHYS-9', 20, '2026-10-20', 'Physics 9 — Motion quiz', 20, (SELECT id FROM u WHERE key = 'tarek'));

INSERT INTO quiz_results (user_id, quiz_id, marks, status)
SELECT u.id, q.id, r.marks, 'graded'
FROM quizzes q, (VALUES ('layla', 18.0), ('omar', 15.0), ('nadia', 19.5), ('youssef', 12.0)) AS r (key, marks)
JOIN u USING (key);

-- Report with results -------------------------------------------------------------
INSERT INTO reports (relevant, type, title, content, created_by, audience_type, is_published) VALUES
    ('exam', 'academic', 'Grade 9 Mathematics — Midterm summary',
     'Class average 82.5 after resits. One student absent on medical leave.',
     (SELECT id FROM u WHERE key = 'mona'), 'supervisors', true);

INSERT INTO report_creators (report_id, reporter_id, role) SELECT r.id, u.id, 'author' FROM reports r, u WHERE u.key = 'mona';
INSERT INTO class_reports (class_code, report_id, created_by) SELECT 'G9-A', r.id, u.id FROM reports r, u WHERE u.key = 'mona';
INSERT INTO exam_reports (exam_id, report_id) SELECT e.id, r.id FROM exams e, reports r;
INSERT INTO results (report_id, marks, remarks, status) SELECT id, 82.5, 'Class average', 'final' FROM reports;

-- Attendance ----------------------------------------------------------------------
INSERT INTO attendance (schedule_id, date, status) SELECT id, DATE '2026-10-04', 'closed' FROM s WHERE slot = 1;

INSERT INTO user_attendance (user_id, attendance_id, status, remarks)
SELECT u.id, a.id, r.status, r.remarks
FROM attendance a, (VALUES ('layla', 'present', NULL), ('omar', 'late', 'Arrived 08:20'),
                           ('nadia', 'present', NULL), ('youssef', 'absent', NULL)) AS r (key, status, remarks)
JOIN u USING (key);

-- Leave: a request with a two-level approval chain ----------------------------------
INSERT INTO leave_types (name, type, max_days) VALUES ('Annual leave', 'paid', 21), ('Sick leave', 'paid', 14);

INSERT INTO user_role_leave_types (user_id, role_code, leave_type_id)
SELECT u.id, 'TEACHER', lt.id FROM u, leave_types lt WHERE u.key IN ('mona', 'tarek');

INSERT INTO leave_requests (user_id, reason, start_date, end_date, leave_type_id)
SELECT u.id, 'Family event', DATE '2026-12-01', DATE '2026-12-03', lt.id
FROM u, leave_types lt WHERE u.key = 'tarek' AND lt.name = 'Annual leave';

INSERT INTO leave_request_approvals (leave_request_id, approver_id, approval_level, status, approval_timestamp)
SELECT lr.id, u.id, a.level, a.status, a.at
FROM leave_requests lr,
     (VALUES ('hassan', 1, 'approved', TIMESTAMPTZ '2026-11-20 10:15+02'),
             ('amina',  2, 'pending',  NULL)) AS a (key, level, status, at)
JOIN u USING (key);

-- Schedule swaps --------------------------------------------------------------------
INSERT INTO swap_configs (swap_type, allow_cross_branch, max_swaps_per_month, min_notice_hours, created_by)
SELECT 'teacher-shift', false, 2, 48, id FROM u WHERE key = 'amina';

INSERT INTO swap_config_approver_roles (swap_config_id, approval_role) SELECT id, 'SUPERVISOR' FROM swap_configs;
INSERT INTO role_swap_configs (role_code, swap_config_id, can_approve, can_initiate)
SELECT r.role_code, c.id, r.approve, r.initiate
FROM swap_configs c, (VALUES ('SUPERVISOR', true, false), ('TEACHER', false, true)) AS r (role_code, approve, initiate);

INSERT INTO swap_requests (user_id, reason, original_schedule_id, requested_schedule_id, created_by, swap_config_id)
SELECT u.id, 'Clinic appointment', s1.id, s2.id, u.id, c.id
FROM u, s s1, s s2, swap_configs c WHERE u.key = 'mona' AND s1.slot = 1 AND s2.slot = 2;

INSERT INTO swap_approvals (swap_request_id, approver_id) SELECT r.id, u.id FROM swap_requests r, u WHERE u.key = 'hassan';

-- Announcements and notifications ---------------------------------------------------
INSERT INTO announcements (title, description, created_by)
SELECT 'Midterm timetable published', 'Midterms run 15–19 November. Check your class schedule.', id FROM u WHERE key = 'hassan';
INSERT INTO announcement_roles (announcement_id, role_code) SELECT id, r FROM announcements, unnest(ARRAY['TEACHER', 'STUDENT']) AS r;
INSERT INTO branch_announcements (branch_code, announcement_id) SELECT 'NILE-MAADI', id FROM announcements;

INSERT INTO notifications (title, content, priority, created_by)
SELECT 'Resit result available', 'Your Mathematics 9 resit has been graded.', 'high', id FROM u WHERE key = 'mona';
INSERT INTO user_notifications (user_id, notification_id) SELECT u.id, n.id FROM notifications n, u WHERE u.key = 'omar';

-- Audit log --------------------------------------------------------------------------
INSERT INTO logs (user_id, session_id, ip_address, description)
SELECT id, 'sess-7f3a9c', '203.0.113.24', 'Recorded midterm marks for G9-A' FROM u WHERE key = 'mona';
INSERT INTO log_actions (log_id, action) SELECT id, a FROM logs, unnest(ARRAY['login', 'marks.record']) AS a;

COMMIT;
