# Relational mapping

The 60 relations produced by mapping the ER model, transcribed from
[the diagram](../diagrams/06-relational-mapping.webp). Key attributes are in
**bold**. This is the logical design as originally drawn; the right-hand
column shows the table that implements each relation in
[`sql/schema.sql`](../sql/schema.sql). Differences between the two are explained
in the [README](../README.md#design-review-what-changed-between-the-mapping-and-the-sql).

| # | Relation (as designed) | SQL table |
| --- | --- | --- |
| 1 | User(**ID**, **Email**, FirstName, LastName, DoB, Picture, Gender, Status, SupervisorId, BranchCode, Password, PasswordChangedAt, PasswordResetToken, PasswordResetExpires, CreatedAt, UpdatedAt) | `users` |
| 2 | UserPhone(**UserId**, **ContactInfo**, PhoneType) | `user_phones` |
| 3 | UserAttendance(**UserId**, **AttendanceId**, Remarks, Status) | `user_attendance` |
| 4 | UserRole(**UserId**, **RoleCode**, StartDate) | `user_roles` |
| 5 | UserClass(**UserId**, **ClassId**, AssignedBy, DateAssigned) | `user_classes` |
| 6 | UserSubject(**UserId**, **SubjectId**, AssignedBy, DateAssigned) | `user_subjects` |
| 7 | ExamResult(**UserId**, **ExamId**, Marks, Status, Feedback, IsAbsent, AttemptNumber) | `exam_results` |
| 8 | QuizResult(**UserId**, **QuizId**, Marks, Status, Feedback, IsAbsent, AttemptNumber) | `quiz_results` |
| 9 | UserSchedule(**UserId**, **ScheduleId**, AssignedBy, DateAssigned) | `user_schedules` |
| 10 | UserRoleLeaveType(**UserId**, **RoleId**, **LeaveTypeId**) | `user_role_leave_types` |
| 11 | UserReport(**UserId**, **ReportId**) | `user_reports` |
| 12 | UserNotification(**UserId**, **NotificationId**, IsRead) | `user_notifications` |
| 13 | Role(**RoleCode**, Name, IsGlobalAdmin, Description, CreatedAt, UpdatedAt) | `roles` |
| 14 | RolePermission(**RoleCode**, **PermissionCode**) | `role_permissions` |
| 15 | RoleSwapConfig(**RoleCode**, **SwapConfigId**, CanApprove, CanInitiate) | `role_swap_configs` |
| 16 | School(**SchoolCode**, **PrincipalName**, **WebsiteUrl**, Logo, ManagerId, SchoolType, CreatedAt, UpdatedAt) | `schools` |
| 17 | SchoolFounder(**SchoolCode**, **Founder**, StartDate) | `school_founders` |
| 18 | Branch(**SchoolCode**, **BranchCode**, BranchName, IsActive, BranchType, ManagerId, EstablishedDate, AddressId, LocationId, CreatedAt, UpdatedAt) | `branches` |
| 19 | BranchEmail(**BranchCode**, **Email**) | `branch_emails` |
| 20 | BranchContactInfo(**BranchCode**, **ContactInfo**, Type, IsPrimary) | `branch_contact_info` |
| 21 | BranchClass(**BranchCode**, **ClassCode**, AddedBy, CreatedAt) | `branch_classes` |
| 22 | BranchSubject(**BranchCode**, **SubjectCode**, AddedBy, CreatedAt) | `branch_subjects` |
| 23 | BranchExam(**BranchCode**, **ExamId**, AddedBy, CreatedAt) | `branch_exams` |
| 24 | BranchQuiz(**BranchCode**, **QuizId**, AddedBy, CreatedAt) | `branch_quizzes` |
| 25 | BranchSchedule(**BranchCode**, **ScheduleId**, AddedBy, CreatedAt) | `branch_schedules` |
| 26 | BranchAnnouncement(**BranchCode**, **AnnouncementId**, AddedBy, CreatedAt) | `branch_announcements` |
| 27 | Class(**ClassCode**, ClassType, Name, Notes, AcademicYear, Section, GradeLevel, Capacity, ManagerId, ScheduleId, CreatedAt, UpdatedAt) | `classes` |
| 28 | ClassSubject(**ClassCode**, **SubjectCode**, AcademicYear) | `class_subjects` |
| 29 | ClassReport(**ClassCode**, **ReportId**, CreatedBy) | `class_reports` |
| 30 | Subject(**SubjectCode**, SubjectType, Name, Description, Units, CreatedAt, UpdatedAt) | `subjects` |
| 31 | SubjectPreRequisite(**SubjectCode**, **PreRequisiteSubjectCode**) | `subject_prerequisites` |
| 32 | Schedule(**Id**, StartTime, EndTime, CreatedAt, UpdatedAt) | `schedules` |
| 33 | ScheduleDays(**ScheduleId**, **DaysOfTheWeek**) | `schedule_days` |
| 34 | SwapRequest(**UserId**, **Id**, Reason, OriginalSchId, RequestedSchId, CreatedBy, SwapConfigId, CreatedAt, UpdatedAt) | `swap_requests` |
| 35 | SwapApproval(**SwapRequestId**, **ApprovalId**, ApproverId, Status, Note) | `swap_approvals` |
| 36 | SwapConfig(**Id**, SwapType, IsEnables, AllowCrossBranch, MaxSwapPerMonth, MinNoticeHours, CreatedBy) | `swap_configs` |
| 37 | SwapConfigApproverRoles(**SwapConfigId**, **ApprovalRole**, CreatedBy) | `swap_config_approver_roles` |
| 38 | Exam(**SubjectCode**, **ExamId**, Type, Duration, Date, Title, Marks, ReportId, CreatedBy, CreatedAt, UpdatedAt) | `exams` |
| 39 | ExamSchedule(**SubjectCode**, **ExamId**, **ScheduleId**) | `exam_schedules` |
| 40 | ExamReport(**SubjectCode**, **ExamId**, **ReportId**) | `exam_reports` |
| 41 | Quiz(**SubjectCode**, **QuizId**, Duration, Date, Title, Marks, ReportId, CreatedBy, CreatedAt, UpdatedAt) | `quizzes` |
| 42 | QuizSchedule(**SubjectCode**, **QuizId**, **ScheduleId**) | `quiz_schedules` |
| 43 | QuizReport(**SubjectCode**, **QuizId**, **ReportId**) | `quiz_reports` |
| 44 | Report(**Id**, Relevant, Type, Date, Title, Content, CreatedBy, AudienceType, IsPublished, CreatedAt, UpdatedAt) | `reports` |
| 45 | ReportCreators(**ReportId**, **RepoterId**, Role) | `report_creators` |
| 46 | Result(**ReportId**, **Id**, Marks, Remarks, Status, CreatedAt, UpdatedAt) | `results` |
| 47 | Announcement(**Id**, Title, PublishDate, Description, CreatedBy, CreatedAt, UpdatedAt) | `announcements` |
| 48 | AnnouncementRole(**AnnouncementId**, **RoleId**, CreatedAt, UpdatedAt) | `announcement_roles` |
| 49 | AnnouncementBy(**AnnouncementId**, **MediaUrl**, MediaType) | `announcement_media` |
| 50 | Location(**Id**, MapUrl, Description, Latitude, Longitude, Geofence, CreatedBy, CreatedAt, UpdatedAt) | `locations` |
| 51 | Address(**Id**, Country, StreetName, BlockNumber, ZipCode, LandMark, CreatedBy, CreatedAt, UpdatedAt) | `addresses` |
| 52 | Address(**Id**, **City**, **State**) | merged into `addresses` |
| 53 | Notification(**Id**, Date, Title, CreatedBy, Description, Content, Priority, CreatedAt, UpdatedAt) | `notifications` |
| 54 | NotificationRole(**NotificationId**, **RoleId**) | `notification_roles` |
| 55 | Log(**UserId**, **LogId**, SessionId, IPAddress, Description, CreatedAt, UpdatedAt) | `logs` |
| 56 | UserLogAction(**UserId**, **Id**, **Action**) | `log_actions` |
| 57 | LeaveRequest(**UserId**, **Id**, Reason, StartDate, EndDate, LeaveTypeId, Status, CreatedAt, UpdatedAt) | `leave_requests` |
| 58 | LeaveRequestApprovals(**LeaveRequestId**, **ApproversId**, Status, ApprovalLevel, Remarks, ApprovalTimestamp) | `leave_request_approvals` |
| 59 | LeaveType(**Id**, Name, Type, Description, MaxDays) | `leave_types` |
| 60 | Attendance(**ScheduleId**, **Id**, Remarks, Status, Date) | `attendance` |
