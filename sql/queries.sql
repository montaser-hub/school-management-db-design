-- =============================================================================
-- Example queries: questions the schema is designed to answer.
-- Run after schema.sql and sample-data.sql.
-- =============================================================================

-- 1. A teacher's weekly timetable
SELECT u.first_name || ' ' || u.last_name AS teacher,
       sd.day_of_week,
       to_char(s.start_time, 'HH24:MI') || '–' || to_char(s.end_time, 'HH24:MI') AS slot
FROM users u
JOIN user_schedules us ON us.user_id = u.id
JOIN schedules s       ON s.id = us.schedule_id
JOIN schedule_days sd  ON sd.schedule_id = s.id
WHERE u.email = 'mona.saleh@nileacademy.example'
ORDER BY array_position(ARRAY['saturday','sunday','monday','tuesday','wednesday','thursday','friday'], sd.day_of_week::text),
         s.start_time;

-- 2. Exam results per student, keeping only each student's latest attempt
SELECT e.title,
       u.first_name || ' ' || u.last_name AS student,
       r.attempt_number,
       CASE WHEN r.is_absent THEN 'absent' ELSE r.marks::text END AS marks,
       r.status
FROM exams e
JOIN LATERAL (
    SELECT DISTINCT ON (user_id) *
    FROM exam_results
    WHERE exam_id = e.id
    ORDER BY user_id, attempt_number DESC
) r ON true
JOIN users u ON u.id = r.user_id
ORDER BY r.marks DESC NULLS LAST;

-- 3. Class average and pass rate per exam (latest attempts, absentees excluded)
WITH latest AS (
    SELECT DISTINCT ON (exam_id, user_id) *
    FROM exam_results
    ORDER BY exam_id, user_id, attempt_number DESC
)
SELECT e.title,
       count(*) FILTER (WHERE NOT l.is_absent)                                   AS sat,
       count(*) FILTER (WHERE l.is_absent)                                       AS absent,
       round(avg(l.marks), 1)                                                    AS average,
       round(100.0 * count(*) FILTER (WHERE l.marks >= e.marks * 0.5)
                   / NULLIF(count(*) FILTER (WHERE NOT l.is_absent), 0), 0)      AS pass_rate_pct
FROM exams e
JOIN latest l ON l.exam_id = e.id
GROUP BY e.id, e.title;

-- 4. Leave requests waiting on a specific approver. A level is only "waiting"
--    once every earlier level has approved.
SELECT lr.id AS request,
       requester.first_name || ' ' || requester.last_name AS requested_by,
       lt.name AS leave_type,
       lr.start_date, lr.end_date,
       a.approval_level
FROM leave_request_approvals a
JOIN leave_requests lr ON lr.id = a.leave_request_id
JOIN users requester   ON requester.id = lr.user_id
JOIN leave_types lt    ON lt.id = lr.leave_type_id
JOIN users approver    ON approver.id = a.approver_id
WHERE approver.email = 'amina.farid@nileacademy.example'
  AND a.status = 'pending'
  AND NOT EXISTS (
      SELECT 1 FROM leave_request_approvals earlier
      WHERE earlier.leave_request_id = a.leave_request_id
        AND earlier.approval_level < a.approval_level
        AND earlier.status <> 'approved'
  );

-- 5. Attendance summary for a class session
SELECT a.date,
       count(*) FILTER (WHERE ua.status = 'present') AS present,
       count(*) FILTER (WHERE ua.status = 'late')    AS late,
       count(*) FILTER (WHERE ua.status = 'absent')  AS absent
FROM attendance a
JOIN user_attendance ua ON ua.attendance_id = a.id
GROUP BY a.id, a.date;

-- 6. Who may approve a swap request, according to its configuration
SELECT sr.id AS swap_request,
       requester.first_name || ' ' || requester.last_name AS requested_by,
       approver.first_name  || ' ' || approver.last_name  AS can_be_approved_by,
       ar.approval_role
FROM swap_requests sr
JOIN users requester               ON requester.id = sr.user_id
JOIN swap_config_approver_roles ar ON ar.swap_config_id = sr.swap_config_id
JOIN user_roles ur                 ON ur.role_code = ar.approval_role
JOIN users approver                ON approver.id = ur.user_id;

-- 7. Announcements visible to a user through their roles and branch
SELECT DISTINCT an.title, an.publish_date
FROM users u
JOIN user_roles ur          ON ur.user_id = u.id
JOIN announcement_roles ar  ON ar.role_code = ur.role_code
JOIN announcements an       ON an.id = ar.announcement_id
JOIN branch_announcements ba ON ba.announcement_id = an.id AND ba.branch_code = u.branch_code
WHERE u.email = 'layla.ibrahim@nileacademy.example';

-- 8. Subjects a student may not take yet: prerequisites they have not passed
SELECT s.name AS subject, pre.name AS missing_prerequisite
FROM subjects s
JOIN subject_prerequisites sp ON sp.subject_code = s.subject_code
JOIN subjects pre             ON pre.subject_code = sp.prerequisite_subject_code
WHERE NOT EXISTS (
    SELECT 1
    FROM exam_results er
    JOIN exams e ON e.id = er.exam_id
    JOIN users u ON u.id = er.user_id
    WHERE e.subject_code = pre.subject_code
      AND u.email = 'youssef.adel@nileacademy.example'
      AND er.status = 'passed'
);
