-- =============================================================================
-- Constraint tests: proves the schema rejects invalid data and that cascades
-- and triggers behave as designed. Runs inside a transaction that is rolled
-- back, so it leaves the database untouched.
--
--   psql -v ON_ERROR_STOP=1 -f sql/tests.sql      (after schema + sample data)
--
-- Any failed expectation raises an exception and stops the script.
-- =============================================================================

BEGIN;

-- Runs `statement` and passes only if it fails with the expected SQLSTATE.
CREATE FUNCTION pg_temp.expect_error(label text, expected_state text, statement text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE statement;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = expected_state THEN
            RAISE NOTICE 'PASS  rejects: %', label;
            RETURN;
        END IF;
        RAISE EXCEPTION 'FAIL  %: expected SQLSTATE %, got % (%)', label, expected_state, SQLSTATE, SQLERRM;
    END;
    RAISE EXCEPTION 'FAIL  %: statement was accepted', label;
END;
$$;

CREATE FUNCTION pg_temp.expect_true(label text, condition boolean) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF condition IS TRUE THEN
        RAISE NOTICE 'PASS  %', label;
    ELSE
        RAISE EXCEPTION 'FAIL  %', label;
    END IF;
END;
$$;

-- SQLSTATEs: 23514 check_violation · 23505 unique_violation · 23503 foreign_key_violation

SELECT pg_temp.expect_error('a user supervising themselves', '23514',
    $$UPDATE users SET supervisor_id = id WHERE email = 'mona.saleh@nileacademy.example'$$);

SELECT pg_temp.expect_error('a duplicate email', '23505',
    $$INSERT INTO users (email, first_name, last_name, password_hash)
      VALUES ('mona.saleh@nileacademy.example', 'Other', 'Mona', 'x')$$);

SELECT pg_temp.expect_error('an email that is not lower-case', '23514',
    $$INSERT INTO users (email, first_name, last_name, password_hash)
      VALUES ('Someone@NileAcademy.example', 'Some', 'One', 'x')$$);

SELECT pg_temp.expect_error('a schedule that ends before it starts', '23514',
    $$INSERT INTO schedules (start_time, end_time) VALUES ('10:00', '09:00')$$);

SELECT pg_temp.expect_error('a subject that is its own prerequisite', '23514',
    $$INSERT INTO subject_prerequisites VALUES ('MATH-9', 'MATH-9')$$);

SELECT pg_temp.expect_error('marks recorded for an absent student', '23514',
    $$UPDATE exam_results SET marks = 50 WHERE is_absent$$);

SELECT pg_temp.expect_error('a leave request that ends before it starts', '23514',
    $$INSERT INTO leave_requests (user_id, start_date, end_date, leave_type_id)
      SELECT u.id, DATE '2026-12-10', DATE '2026-12-01', lt.id
      FROM users u, leave_types lt WHERE u.email LIKE 'mona%' LIMIT 1$$);

SELECT pg_temp.expect_error('two approvers at the same approval level', '23505',
    $$INSERT INTO leave_request_approvals (leave_request_id, approver_id, approval_level)
      SELECT lr.id, u.id, 1 FROM leave_requests lr, users u WHERE u.email LIKE 'mona%'$$);

SELECT pg_temp.expect_error('swapping a schedule for itself', '23514',
    $$INSERT INTO swap_requests (user_id, original_schedule_id, requested_schedule_id, swap_config_id)
      SELECT u.id, s.id, s.id, c.id FROM users u, schedules s, swap_configs c
      WHERE u.email LIKE 'tarek%' LIMIT 1$$);

SELECT pg_temp.expect_error('a leave entitlement for a role the user does not hold', '23503',
    $$INSERT INTO user_role_leave_types (user_id, role_code, leave_type_id)
      SELECT u.id, 'ADMIN', lt.id FROM users u, leave_types lt WHERE u.email LIKE 'layla%' LIMIT 1$$);

SELECT pg_temp.expect_error('a second primary contact for one branch', '23505',
    $$INSERT INTO branch_contact_info VALUES ('NILE-MAADI', '+20 2 5550 1999', 'phone', true)$$);

SELECT pg_temp.expect_error('two attendance sessions for one schedule on one day', '23505',
    $$INSERT INTO attendance (schedule_id, date) SELECT schedule_id, date FROM attendance LIMIT 1$$);

SELECT pg_temp.expect_error('a branch that belongs to no known school', '23503',
    $$INSERT INTO branches (branch_code, school_code, branch_name) VALUES ('X-1', 'NOPE', 'Ghost Campus')$$);

-- Cascades and triggers -------------------------------------------------------

-- Renaming a role code follows through to everything that references it
UPDATE roles SET role_code = 'INSTRUCTOR' WHERE role_code = 'TEACHER';
SELECT pg_temp.expect_true('renaming a role code cascades to user_roles and leave entitlements',
    (SELECT count(*) FROM user_roles WHERE role_code = 'INSTRUCTOR') = 2
    AND (SELECT count(*) FROM user_role_leave_types WHERE role_code = 'INSTRUCTOR') = 4
    AND NOT EXISTS (SELECT 1 FROM user_roles WHERE role_code = 'TEACHER'));

-- Weak entities disappear with their owner
DELETE FROM reports;
SELECT pg_temp.expect_true('deleting a report removes its results but keeps the exam',
    NOT EXISTS (SELECT 1 FROM results) AND EXISTS (SELECT 1 FROM exams));

DELETE FROM users WHERE email = 'tarek.nasser@nileacademy.example';
SELECT pg_temp.expect_true('deleting a user removes their leave requests and approvals, keeps their quiz',
    NOT EXISTS (SELECT 1 FROM leave_requests)
    AND NOT EXISTS (SELECT 1 FROM leave_request_approvals)
    AND (SELECT created_by IS NULL FROM quizzes LIMIT 1));

-- updated_at is maintained by trigger. Timestamps are frozen inside a
-- transaction (now() is the transaction start), so backdate the row first.
ALTER TABLE subjects DISABLE TRIGGER subjects_set_updated_at;
UPDATE subjects SET updated_at = now() - interval '1 day' WHERE subject_code = 'PHYS-9';
ALTER TABLE subjects ENABLE TRIGGER subjects_set_updated_at;
UPDATE subjects SET units = 4 WHERE subject_code = 'PHYS-9';
SELECT pg_temp.expect_true('updated_at is refreshed by the trigger on update',
    (SELECT updated_at = now() FROM subjects WHERE subject_code = 'PHYS-9'));

ROLLBACK;
