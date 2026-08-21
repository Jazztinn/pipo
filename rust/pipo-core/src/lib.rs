//! JSON-lines sidecar for Pipo. The Moodle request shape is adapted from
//! ALinuxPerson/openlms-mcp at c5a09e9f70d56def5e26acea425d1a7dfd514503.
//! Pipo intentionally exposes a small read-only subset and no network listener.

use std::{collections::HashSet, time::Duration};

use futures_util::{StreamExt, stream};
use reqwest::{Client, redirect};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use thiserror::Error;
use time::{OffsetDateTime, format_description::well_known::Rfc3339};
use url::Url;

pub const PROTOCOL_VERSION: u8 = 2;
pub const LMS_ORIGIN: &str = "https://lms.lpucavite.edu.ph";
pub const REQUEST_CAP_BYTES: usize = 2 * 1024 * 1024;
const RESPONSE_CAP_BYTES: usize = 2 * 1024 * 1024;
const TOKEN_RESPONSE_CAP_BYTES: usize = 256 * 1024;
const SERVICE: &str = "moodle_mobile_app";
const CALENDAR_EVENT_LIMIT: usize = 30;
const ANNOUNCEMENT_LIMIT: usize = 20;
const RESOURCE_LIMIT: usize = 30;
const ASSIGNMENT_STATUS_LIMIT: usize = 30;
const ASSIGNMENT_STATUS_CONCURRENCY: usize = 4;
const DASHBOARD_SECTIONS: &[&str] = &[
    "schedule",
    "due_soon",
    "assignments",
    "announcements",
    "messages",
    "grades",
    "resources",
];

#[derive(Debug, Deserialize)]
pub struct Request {
    pub version: u8,
    pub id: String,
    pub method: Method,
    #[serde(default)]
    pub params: Value,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Method {
    AuthenticateWithPassword,
    AuthenticateWithToken,
    DiscoverCapabilities,
    RefreshDashboard,
    LoadCourse,
    ResolveDestination,
}

#[derive(Debug, Serialize)]
pub struct Response {
    pub version: u8,
    pub id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ErrorEnvelope>,
}

#[derive(Debug, Serialize)]
pub struct ErrorEnvelope {
    pub code: &'static str,
    pub message: String,
}

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("invalid request: {0}")]
    Input(String),
    #[error("authentication failed: {0}")]
    Authentication(String),
    #[error("network request failed: {0}")]
    Network(String),
    #[error("invalid Moodle response: {0}")]
    Response(String),
    #[error("unsupported by this LMS: {0}")]
    Unsupported(String),
    #[error("destination is outside the LPU LMS origin")]
    Origin,
}

impl CoreError {
    fn code(&self) -> &'static str {
        match self {
            Self::Input(_) | Self::Origin => "invalid_input",
            Self::Authentication(_) => "authentication_failed",
            Self::Network(_) => "network_failed",
            Self::Response(_) => "invalid_response",
            Self::Unsupported(_) => "unsupported",
        }
    }
}

impl From<reqwest::Error> for CoreError {
    fn from(value: reqwest::Error) -> Self {
        let detail = if value.is_timeout() {
            "request timed out".to_owned()
        } else {
            value.without_url().to_string()
        };
        Self::Network(redact(&detail))
    }
}

#[derive(Clone)]
pub struct MoodleClient {
    http: Client,
    origin: Url,
}

impl MoodleClient {
    pub fn production() -> Result<Self, CoreError> {
        Self::new(
            Url::parse(LMS_ORIGIN).expect("fixed LMS origin is valid"),
            false,
        )
    }

    fn new(origin: Url, allow_test_origin: bool) -> Result<Self, CoreError> {
        if !allow_test_origin && origin.as_str().trim_end_matches('/') != LMS_ORIGIN {
            return Err(CoreError::Origin);
        }
        if origin.scheme() != "https" && !allow_test_origin {
            return Err(CoreError::Origin);
        }
        let fixed_origin = origin.origin().ascii_serialization();
        let redirects = redirect::Policy::custom(move |attempt| {
            if attempt.previous().len() >= 5 {
                return attempt.error("too many redirects");
            }
            if attempt.url().origin().ascii_serialization() == fixed_origin {
                attempt.follow()
            } else {
                attempt.stop()
            }
        });
        let http = Client::builder()
            .connect_timeout(Duration::from_secs(10))
            .timeout(Duration::from_secs(30))
            .redirect(redirects)
            .user_agent(concat!("pipo-core/", env!("CARGO_PKG_VERSION")))
            .build()
            .map_err(CoreError::from)?;
        Ok(Self { http, origin })
    }

    #[cfg(test)]
    pub fn for_test(origin: Url) -> Result<Self, CoreError> {
        Self::new(origin, true)
    }

    fn endpoint(&self, path: &str) -> Result<Url, CoreError> {
        self.origin
            .join(path)
            .map_err(|error| CoreError::Input(error.to_string()))
    }

    pub async fn authenticate_with_password(
        &self,
        username: &str,
        password: &str,
    ) -> Result<Value, CoreError> {
        if username.trim().is_empty() || password.is_empty() {
            return Err(CoreError::Input(
                "username and password are required".to_owned(),
            ));
        }
        let value = self
            .post_form(
                self.endpoint("login/token.php")?,
                vec![
                    ("username".to_owned(), username.to_owned()),
                    ("password".to_owned(), password.to_owned()),
                    ("service".to_owned(), SERVICE.to_owned()),
                ],
                TOKEN_RESPONSE_CAP_BYTES,
            )
            .await?;
        let token = value
            .get("token")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                let message = value
                    .get("error")
                    .or_else(|| value.get("message"))
                    .and_then(Value::as_str)
                    .unwrap_or("token response omitted a token");
                CoreError::Authentication(redact(message))
            })?;
        Ok(json!({ "token": token }))
    }

    pub async fn authenticate_with_token(&self, token: &str) -> Result<Value, CoreError> {
        let site = self.site_info(token).await?;
        Ok(json!({ "site": safe_site(&site) }))
    }

    pub async fn discover_capabilities(&self, token: &str) -> Result<Value, CoreError> {
        let site = self.site_info(token).await?;
        let functions = site
            .get("functions")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|item| item.get("name").or(Some(item)).and_then(Value::as_str))
            .map(str::to_owned)
            .collect::<Vec<_>>();
        Ok(
            json!({ "site": safe_site(&site), "functions": functions, "supported": capability_support(&site), "read_only": true }),
        )
    }

    pub async fn refresh_dashboard(
        &self,
        token: &str,
        requested_sections: Option<&[Value]>,
    ) -> Result<Value, CoreError> {
        let requested = normalize_sections(requested_sections)?;
        let site = self.site_info(token).await?;
        let user_id = site
            .get("userid")
            .and_then(Value::as_i64)
            .ok_or_else(|| CoreError::Response("site info omitted userid".to_owned()))?;
        let capabilities = capabilities(&site);
        let courses_raw = self
            .call(
                token,
                "core_enrol_get_users_courses",
                json!({ "userid": user_id }),
            )
            .await?;
        let courses = courses_raw
            .as_array()
            .cloned()
            .unwrap_or_default()
            .into_iter()
            .filter(|course| course.get("visible").and_then(Value::as_i64).unwrap_or(1) != 0)
            .map(course_summary)
            .collect::<Vec<_>>();

        let mut failures = Vec::new();
        let mut section_timestamps = Map::new();
        let now = unix_now();
        let wants_calendar = requested.contains("due_soon") || requested.contains("schedule");
        let events = if wants_calendar
            && capabilities.contains("core_calendar_get_action_events_by_timesort")
        {
            match self.call(
                token,
                "core_calendar_get_action_events_by_timesort",
                json!({ "timesortfrom": now, "timesortto": now + (7 * 24 * 60 * 60), "limitnum": CALENDAR_EVENT_LIMIT }),
            )
            .await {
                Ok(value) => {
                    if requested.contains("due_soon") { section_timestamps.insert("due_soon".to_owned(), Value::String(rfc3339_now())); }
                    if requested.contains("schedule") { section_timestamps.insert("schedule".to_owned(), Value::String(rfc3339_now())); }
                    value
                }
                Err(error) => {
                    if requested.contains("due_soon") { failures.push(section_failure("Due soon", &error)); }
                    if requested.contains("schedule") { failures.push(section_failure("Schedule", &error)); }
                    Value::Null
                }
            }
        } else {
            Value::Null
        };
        let calendar_items = events
            .get("events")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .map(event_item)
            .collect::<Vec<_>>();
        let due_soon = if requested.contains("due_soon") {
            calendar_items
                .clone()
                .into_iter()
                .map(|item| with_section(item, "due_soon"))
                .collect()
        } else {
            Vec::new()
        };
        let schedule = if requested.contains("schedule") {
            calendar_items
                .into_iter()
                .filter(|item| timestamp_is_today(item.get("timestamp").and_then(Value::as_str)))
                .map(|item| with_section(item, "schedule"))
                .collect::<Vec<_>>()
        } else {
            Vec::new()
        };
        let due_ids = due_soon
            .iter()
            .filter_map(|item| item.get("destination").and_then(Value::as_str))
            .collect::<HashSet<_>>();

        let notifications = if requested.contains("notifications")
            && capabilities.contains("message_popup_get_popup_notifications")
        {
            match self
                .call(
                    token,
                    "message_popup_get_popup_notifications",
                    json!({ "limit": 20, "offset": 0 }),
                )
                .await
            {
                Ok(value) => {
                    section_timestamps
                        .insert("notifications".to_owned(), Value::String(rfc3339_now()));
                    value
                }
                Err(error) => {
                    failures.push(section_failure("Notifications", &error));
                    Value::Null
                }
            }
        } else {
            Value::Null
        };
        let notifications = notifications
            .get("notifications")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .map(notification_item)
            .filter(|item| item.get("is_unread") == Some(&Value::Bool(true)))
            .collect::<Vec<_>>();

        let assignments = if requested.contains("assignments")
            && capabilities.contains("mod_assign_get_assignments")
        {
            match self.call(token, "mod_assign_get_assignments", json!({ "courseids": courses.iter().filter_map(|course| course.get("id").and_then(Value::as_i64)).collect::<Vec<_>>() })).await {
                Ok(value) => { section_timestamps.insert("assignments".to_owned(), Value::String(rfc3339_now())); value },
                Err(error) => {
                    failures.push(section_failure("Assignments", &error));
                    Value::Null
                }
            }
        } else {
            Value::Null
        };
        let mut assignment_items = assignment_items(&assignments)
            .into_iter()
            .map(|item| with_section(item, "assignments"))
            .collect::<Vec<_>>();
        if requested.contains("assignments")
            && capabilities.contains("mod_assign_get_submission_status")
        {
            let assignments_for_status = assignment_items
                .iter()
                .take(ASSIGNMENT_STATUS_LIMIT)
                .cloned()
                .collect::<Vec<_>>();
            let status_results = stream::iter(assignments_for_status.into_iter().map(
                |assignment| async move {
                    let assign_id = assignment
                        .get("id")
                        .and_then(Value::as_i64)
                        .unwrap_or_default();
                    let result = if assign_id > 0 {
                        self.call(
                            token,
                            "mod_assign_get_submission_status",
                            json!({ "assignid": assign_id }),
                        )
                        .await
                    } else {
                        Err(CoreError::Response("assignment omitted id".to_owned()))
                    };
                    (assignment, result)
                },
            ))
            .buffer_unordered(ASSIGNMENT_STATUS_CONCURRENCY)
            .collect::<Vec<_>>()
            .await;
            let mut status_by_id = std::collections::HashMap::new();
            for (assignment, result) in status_results {
                let id = value_identifier(assignment.get("id").unwrap_or(&Value::Null));
                match result {
                    Ok(value) => {
                        status_by_id.insert(id, submission_status(&value));
                    }
                    Err(error) => {
                        failures.push(section_failure("Submission status", &error));
                    }
                }
            }
            for assignment in &mut assignment_items {
                let id = value_identifier(assignment.get("id").unwrap_or(&Value::Null));
                if let Some(status) = status_by_id.get(&id) {
                    assignment
                        .as_object_mut()
                        .expect("assignment object")
                        .insert(
                            "submission_status".to_owned(),
                            Value::String(status.clone()),
                        );
                }
            }
            section_timestamps.insert("submission_status".to_owned(), Value::String(rfc3339_now()));
        }
        let assignment_ids = assignment_items
            .iter()
            .filter_map(|item| item.get("id"))
            .map(value_identifier)
            .collect::<Vec<_>>();
        let new_assignments = assignment_items
            .into_iter()
            .filter(|item| {
                item.get("destination")
                    .and_then(Value::as_str)
                    .map(|destination| !due_ids.contains(destination))
                    .unwrap_or(true)
            })
            .collect::<Vec<_>>();

        let messages = if requested.contains("messages")
            && capabilities.contains("core_message_get_conversations")
        {
            match self.call(token, "core_message_get_conversations", json!({ "userid": user_id, "limitfrom": 0, "limitnum": 10, "type": 0, "favourites": false })).await {
                Ok(value) => { section_timestamps.insert("messages".to_owned(), Value::String(rfc3339_now())); value },
                Err(error) => {
                    failures.push(section_failure("Messages", &error));
                    Value::Null
                }
            }
        } else {
            Value::Null
        };
        let messages = messages
            .get("conversations")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .map(message_item)
            .collect::<Vec<_>>();

        let mut grade_feedback = Vec::new();
        let mut courses_with_grades = Vec::new();
        if requested.contains("grades") && capabilities.contains("gradereport_user_get_grade_items")
        {
            for course in &courses {
                let course_id = course.get("id").and_then(Value::as_i64).unwrap_or_default();
                let grades = match self
                    .call(
                        token,
                        "gradereport_user_get_grade_items",
                        json!({ "courseid": course_id, "userid": user_id }),
                    )
                    .await
                {
                    Ok(value) => value,
                    Err(error) => {
                        failures.push(section_failure("Grades", &error));
                        courses_with_grades.push(course.clone());
                        continue;
                    }
                };
                let published = published_grade_items(&grades, course);
                if let Some(total) = published
                    .iter()
                    .find(|item| item.get("is_total") == Some(&Value::Bool(true)))
                    .and_then(|item| item.get("published_total"))
                    .cloned()
                {
                    let mut with_total = course.clone();
                    with_total
                        .as_object_mut()
                        .expect("course object")
                        .insert("published_total".to_owned(), total);
                    courses_with_grades.push(with_total);
                } else {
                    courses_with_grades.push(course.clone());
                }
                grade_feedback.extend(
                    published
                        .into_iter()
                        .filter(|item| item.get("is_total") != Some(&Value::Bool(true))),
                );
            }
            section_timestamps.insert("grades".to_owned(), Value::String(rfc3339_now()));
        } else {
            courses_with_grades = courses.clone();
        }

        let (announcements, resources) = self
            .dashboard_content(
                token,
                &courses,
                requested.contains("announcements"),
                requested.contains("resources"),
                &capabilities,
                &mut failures,
            )
            .await;
        if requested.contains("announcements")
            && capabilities.contains("mod_forum_get_forum_discussions_paginated")
        {
            section_timestamps.insert("announcements".to_owned(), Value::String(rfc3339_now()));
        }
        if requested.contains("resources") && capabilities.contains("core_course_get_contents") {
            section_timestamps.insert("resources".to_owned(), Value::String(rfc3339_now()));
        }

        let courses_with_counts = courses_with_grades
            .into_iter()
            .map(|mut course| {
                let course_id = course.get("id").and_then(Value::as_i64);
                let count = due_soon
                    .iter()
                    .filter(|item| item.get("course_id").and_then(Value::as_i64) == course_id)
                    .count();
                course
                    .as_object_mut()
                    .expect("course object")
                    .insert("upcoming_count".to_owned(), json!(count));
                course
            })
            .collect::<Vec<_>>();

        Ok(json!({
            "version": PROTOCOL_VERSION,
            "generated_at": rfc3339_now(),
            "site_name": site.get("sitename").and_then(Value::as_str).unwrap_or("LPU Cavite LMS"),
            "student_name": site.get("fullname").and_then(Value::as_str).unwrap_or(""),
            "sections": { "due_soon": due_soon, "notifications": notifications, "new_assignments": new_assignments, "messages": messages, "grade_feedback": grade_feedback },
            "next_up": [],
            "schedule": schedule,
            "announcements": announcements,
            "resources": resources,
            "section_timestamps": section_timestamps,
            "supported": capability_support(&site),
            "assignment_ids": assignment_ids,
            "courses": courses_with_counts,
            "failures": failures
        }))
    }

    pub async fn load_course(&self, token: &str, course_id: i64) -> Result<Value, CoreError> {
        if course_id <= 0 {
            return Err(CoreError::Input("course_id must be positive".to_owned()));
        }
        let site = self.site_info(token).await?;
        let user_id = site
            .get("userid")
            .and_then(Value::as_i64)
            .ok_or_else(|| CoreError::Response("site info omitted userid".to_owned()))?;
        let capabilities = capabilities(&site);
        let courses = self
            .call(
                token,
                "core_enrol_get_users_courses",
                json!({ "userid": user_id }),
            )
            .await?;
        let enrolled = courses
            .as_array()
            .into_iter()
            .flatten()
            .find(|course| course.get("id").and_then(Value::as_i64) == Some(course_id))
            .cloned()
            .ok_or_else(|| {
                CoreError::Input("course is not enrolled for this account".to_owned())
            })?;
        let mut course = course_summary(enrolled);
        let supports_assignments = capabilities.contains("mod_assign_get_assignments");
        let supports_grades = capabilities.contains("gradereport_user_get_grade_items");
        let mut failures = Vec::new();

        let mut assignments = if supports_assignments {
            match self
                .call(
                    token,
                    "mod_assign_get_assignments",
                    json!({ "courseids": [course_id] }),
                )
                .await
            {
                Ok(value) => assignment_items(&value),
                Err(error) => {
                    failures.push(section_failure("Assignments", &error));
                    Vec::new()
                }
            }
        } else {
            Vec::new()
        };

        let supports_submission_status =
            supports_assignments && capabilities.contains("mod_assign_get_submission_status");
        if supports_submission_status {
            self.apply_submission_statuses(token, &mut assignments, &mut failures)
                .await;
        }

        let grades = if supports_grades {
            match self
                .call(
                    token,
                    "gradereport_user_get_grade_items",
                    json!({ "courseid": course_id, "userid": user_id }),
                )
                .await
            {
                Ok(value) => course_grade_items(&value, &course),
                Err(error) => {
                    failures.push(section_failure("Grades", &error));
                    Vec::new()
                }
            }
        } else {
            Vec::new()
        };
        if let Some(total) = grades
            .iter()
            .find(|item| item.get("is_total") == Some(&Value::Bool(true)))
            .and_then(|item| item.get("published_grade"))
            .cloned()
        {
            course
                .as_object_mut()
                .expect("course object")
                .insert("published_total".to_owned(), total);
        }

        let supports_announcements = capabilities.contains("core_course_get_contents")
            && capabilities.contains("mod_forum_get_forum_discussions_paginated");
        let supports_resources = capabilities.contains("core_course_get_contents");
        let contents = if supports_announcements || supports_resources {
            match self
                .call(
                    token,
                    "core_course_get_contents",
                    json!({ "courseid": course_id }),
                )
                .await
            {
                Ok(value) => Some(value),
                Err(error) => {
                    failures.push(section_failure("Course content", &error));
                    None
                }
            }
        } else {
            None
        };
        let announcements = match contents.as_ref() {
            Some(contents) if supports_announcements => {
                self.announcements_from_contents(token, contents, &course, &mut failures)
                    .await
            }
            _ => Vec::new(),
        };
        let resources = match contents.as_ref() {
            Some(contents) if supports_resources => resource_items(contents, &course)
                .into_iter()
                .take(RESOURCE_LIMIT)
                .collect(),
            _ => Vec::new(),
        };

        Ok(json!({
            "version": PROTOCOL_VERSION,
            "course": course,
            "assignments": assignments,
            "grades": grades.into_iter().filter(|item| item.get("is_total") != Some(&Value::Bool(true))).collect::<Vec<_>>(),
            "announcements": announcements,
            "resources": resources,
            "supported": {
                "assignments": supports_assignments,
                "grades": supports_grades,
                "submission_status": supports_submission_status,
                "announcements": supports_announcements,
                "resources": supports_resources
            },
            "destination": format!("/course/view.php?id={course_id}"),
            "failures": failures
        }))
    }

    async fn apply_submission_statuses(
        &self,
        token: &str,
        assignments: &mut [Value],
        failures: &mut Vec<String>,
    ) {
        let source = assignments
            .iter()
            .take(ASSIGNMENT_STATUS_LIMIT)
            .cloned()
            .collect::<Vec<_>>();
        let results = stream::iter(source.into_iter().map(|assignment| async move {
            let assign_id = assignment
                .get("id")
                .and_then(Value::as_i64)
                .unwrap_or_default();
            let result = if assign_id > 0 {
                self.call(
                    token,
                    "mod_assign_get_submission_status",
                    json!({ "assignid": assign_id }),
                )
                .await
            } else {
                Err(CoreError::Response("assignment omitted id".to_owned()))
            };
            (
                value_identifier(assignment.get("id").unwrap_or(&Value::Null)),
                result,
            )
        }))
        .buffer_unordered(ASSIGNMENT_STATUS_CONCURRENCY)
        .collect::<Vec<_>>()
        .await;
        let mut statuses = std::collections::HashMap::new();
        for (id, result) in results {
            match result {
                Ok(value) => {
                    statuses.insert(id, submission_status(&value));
                }
                Err(error) => failures.push(section_failure("Submission status", &error)),
            }
        }
        for assignment in assignments {
            let id = value_identifier(assignment.get("id").unwrap_or(&Value::Null));
            if let Some(status) = statuses.get(&id) {
                assignment
                    .as_object_mut()
                    .expect("assignment object")
                    .insert(
                        "submission_status".to_owned(),
                        Value::String(status.clone()),
                    );
            }
        }
    }

    async fn dashboard_content(
        &self,
        token: &str,
        courses: &[Value],
        wants_announcements: bool,
        wants_resources: bool,
        capabilities: &HashSet<String>,
        failures: &mut Vec<String>,
    ) -> (Vec<Value>, Vec<Value>) {
        if !wants_announcements && !wants_resources
            || !capabilities.contains("core_course_get_contents")
        {
            return (Vec::new(), Vec::new());
        }
        let supports_announcements = wants_announcements
            && capabilities.contains("mod_forum_get_forum_discussions_paginated");
        let mut announcements = Vec::new();
        let mut resources = Vec::new();
        for course in courses {
            if announcements.len() >= ANNOUNCEMENT_LIMIT && resources.len() >= RESOURCE_LIMIT {
                break;
            }
            let Some(course_id) = course.get("id").and_then(Value::as_i64) else {
                continue;
            };
            let contents = match self
                .call(
                    token,
                    "core_course_get_contents",
                    json!({ "courseid": course_id }),
                )
                .await
            {
                Ok(value) => value,
                Err(error) => {
                    failures.push(section_failure("Course content", &error));
                    continue;
                }
            };
            if supports_announcements && announcements.len() < ANNOUNCEMENT_LIMIT {
                announcements.extend(
                    self.announcements_from_contents(token, &contents, course, failures)
                        .await
                        .into_iter()
                        .take(ANNOUNCEMENT_LIMIT - announcements.len()),
                );
            }
            if wants_resources && resources.len() < RESOURCE_LIMIT {
                resources.extend(
                    resource_items(&contents, course)
                        .into_iter()
                        .take(RESOURCE_LIMIT - resources.len()),
                );
            }
        }
        announcements.sort_by_key(|item| {
            std::cmp::Reverse(
                item.get("timestamp")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_owned(),
            )
        });
        (announcements, resources)
    }

    async fn announcements_from_contents(
        &self,
        token: &str,
        contents: &Value,
        course: &Value,
        failures: &mut Vec<String>,
    ) -> Vec<Value> {
        let forums = forum_modules(contents);
        let mut output = Vec::new();
        for forum in forums {
            if output.len() >= ANNOUNCEMENT_LIMIT {
                break;
            }
            let forum_id = match forum.get("instance").and_then(Value::as_i64) {
                Some(value) => value,
                None => continue,
            };
            match self.call(token, "mod_forum_get_forum_discussions_paginated", json!({ "forumid": forum_id, "sortby": "timemodified", "sortdirection": "DESC", "page": 0, "perpage": ANNOUNCEMENT_LIMIT - output.len() })).await {
                Ok(value) => output.extend(value.get("discussions").and_then(Value::as_array).into_iter().flatten().map(|discussion| announcement_item(discussion, course, &forum))),
                Err(error) => failures.push(section_failure("Announcements", &error)),
            }
        }
        output
    }

    pub fn resolve_destination(&self, destination: &str) -> Result<Value, CoreError> {
        let url = self
            .origin
            .join(destination)
            .map_err(|_| CoreError::Origin)?;
        if url.origin() != self.origin.origin() {
            return Err(CoreError::Origin);
        }
        Ok(json!({ "url": url.to_string() }))
    }

    async fn site_info(&self, token: &str) -> Result<Value, CoreError> {
        self.call(token, "core_webservice_get_site_info", json!({}))
            .await
    }

    async fn call(&self, token: &str, function: &str, params: Value) -> Result<Value, CoreError> {
        if token.is_empty() {
            return Err(CoreError::Authentication("token is required".to_owned()));
        }
        let mut form = vec![
            ("wstoken".to_owned(), token.to_owned()),
            ("wsfunction".to_owned(), function.to_owned()),
            ("moodlewsrestformat".to_owned(), "json".to_owned()),
            ("moodlewssettingfilter".to_owned(), "1".to_owned()),
            ("moodlewssettingfileurl".to_owned(), "0".to_owned()),
        ];
        flatten_form(None, &params, &mut form)?;
        let value = self
            .post_form(
                self.endpoint("webservice/rest/server.php")?,
                form,
                RESPONSE_CAP_BYTES,
            )
            .await?;
        if let Some(message) = value
            .get("message")
            .or_else(|| value.get("error"))
            .and_then(Value::as_str)
        {
            let message = redact(message);
            if value
                .get("errorcode")
                .and_then(Value::as_str)
                .is_some_and(|code| matches!(code, "invalidtoken" | "invalidlogin"))
            {
                return Err(CoreError::Authentication(message));
            }
            return Err(CoreError::Response(message));
        }
        Ok(value)
    }

    async fn post_form(
        &self,
        endpoint: Url,
        form: Vec<(String, String)>,
        cap: usize,
    ) -> Result<Value, CoreError> {
        let response = self.http.post(endpoint).form(&form).send().await?;
        parse_json_response(response, cap).await
    }
}

pub async fn handle(request: Request, client: &MoodleClient) -> Response {
    let id = request.id.clone();
    let result = if request.version != PROTOCOL_VERSION {
        Err(CoreError::Input("unsupported protocol version".to_owned()))
    } else {
        dispatch(request, client).await
    };
    match result {
        Ok(result) => match serde_json::to_vec(&result) {
            Ok(encoded) if encoded.len() <= RESPONSE_CAP_BYTES => Response {
                version: PROTOCOL_VERSION,
                id,
                result: Some(result),
                error: None,
            },
            Ok(_) => error_response(
                id,
                CoreError::Response(format!("response exceeds {RESPONSE_CAP_BYTES} byte limit")),
            ),
            Err(error) => error_response(id, CoreError::Response(error.to_string())),
        },
        Err(error) => error_response(id, error),
    }
}

fn error_response(id: String, error: CoreError) -> Response {
    Response {
        version: PROTOCOL_VERSION,
        id,
        result: None,
        error: Some(ErrorEnvelope {
            code: error.code(),
            message: redact(&error.to_string()),
        }),
    }
}

async fn dispatch(request: Request, client: &MoodleClient) -> Result<Value, CoreError> {
    let object = request
        .params
        .as_object()
        .ok_or_else(|| CoreError::Input("params must be an object".to_owned()))?;
    match request.method {
        Method::AuthenticateWithPassword => {
            client
                .authenticate_with_password(
                    required_string(object, "username")?,
                    required_string(object, "password")?,
                )
                .await
        }
        Method::AuthenticateWithToken => {
            client
                .authenticate_with_token(required_string(object, "token")?)
                .await
        }
        Method::DiscoverCapabilities => {
            client
                .discover_capabilities(required_string(object, "token")?)
                .await
        }
        Method::RefreshDashboard => {
            client
                .refresh_dashboard(
                    required_string(object, "token")?,
                    optional_sections(object)?,
                )
                .await
        }
        Method::LoadCourse => {
            client
                .load_course(
                    required_string(object, "token")?,
                    required_i64(object, "course_id")?,
                )
                .await
        }
        Method::ResolveDestination => {
            client.resolve_destination(required_string(object, "destination")?)
        }
    }
}

fn required_string<'a>(object: &'a Map<String, Value>, key: &str) -> Result<&'a str, CoreError> {
    object
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| CoreError::Input(format!("{key} is required")))
}
fn required_i64(object: &Map<String, Value>, key: &str) -> Result<i64, CoreError> {
    object
        .get(key)
        .and_then(Value::as_i64)
        .filter(|value| *value > 0)
        .ok_or_else(|| CoreError::Input(format!("{key} must be positive")))
}
fn optional_sections(object: &Map<String, Value>) -> Result<Option<&[Value]>, CoreError> {
    match object.get("sections") {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Array(value)) => Ok(Some(value)),
        Some(_) => Err(CoreError::Input("sections must be an array".to_owned())),
    }
}

fn normalize_sections(values: Option<&[Value]>) -> Result<HashSet<String>, CoreError> {
    let values = match values {
        Some(value) => value,
        None => {
            return Ok(DASHBOARD_SECTIONS
                .iter()
                .map(|value| (*value).to_owned())
                .collect());
        }
    };
    let mut sections = HashSet::new();
    for value in values {
        let section = value
            .as_str()
            .ok_or_else(|| CoreError::Input("sections must contain strings".to_owned()))?;
        if section == "notifications" || DASHBOARD_SECTIONS.contains(&section) {
            sections.insert(section.to_owned());
        } else {
            return Err(CoreError::Input(format!(
                "unsupported dashboard section: {section}"
            )));
        }
    }
    Ok(sections)
}

async fn parse_json_response(response: reqwest::Response, cap: usize) -> Result<Value, CoreError> {
    if response
        .content_length()
        .is_some_and(|length| length > cap as u64)
    {
        return Err(CoreError::Response(format!(
            "response exceeds {cap} byte limit"
        )));
    }
    let status = response.status();
    let mut bytes = Vec::new();
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(CoreError::from)?;
        if bytes.len().saturating_add(chunk.len()) > cap {
            return Err(CoreError::Response(format!(
                "response exceeds {cap} byte limit"
            )));
        }
        bytes.extend_from_slice(&chunk);
    }
    if !status.is_success() {
        return Err(CoreError::Network(format!("LMS returned HTTP {status}")));
    }
    serde_json::from_slice(&bytes)
        .map_err(|error| CoreError::Response(format!("expected JSON: {error}")))
}

fn flatten_form(
    prefix: Option<&str>,
    value: &Value,
    output: &mut Vec<(String, String)>,
) -> Result<(), CoreError> {
    match value {
        Value::Object(object) => {
            for (key, value) in object {
                let path = prefix
                    .map(|prefix| format!("{prefix}[{key}]"))
                    .unwrap_or_else(|| key.to_owned());
                flatten_form(Some(&path), value, output)?;
            }
        }
        Value::Array(items) => {
            for (index, value) in items.iter().enumerate() {
                let path = format!("{}[{index}]", prefix.unwrap_or(""));
                flatten_form(Some(&path), value, output)?;
            }
        }
        Value::String(value) => output.push((prefix.unwrap_or("").to_owned(), value.clone())),
        Value::Number(value) => output.push((prefix.unwrap_or("").to_owned(), value.to_string())),
        Value::Bool(value) => output.push((
            prefix.unwrap_or("").to_owned(),
            if *value {
                "1".to_owned()
            } else {
                "0".to_owned()
            },
        )),
        Value::Null => {}
    }
    Ok(())
}

fn capabilities(site: &Value) -> HashSet<String> {
    site.get("functions")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|item| item.get("name").or(Some(item)).and_then(Value::as_str))
        .map(str::to_owned)
        .collect()
}
fn capability_support(site: &Value) -> Value {
    let available = capabilities(site);
    json!({
        "due_soon": available.contains("core_calendar_get_action_events_by_timesort"),
        "schedule": available.contains("core_calendar_get_action_events_by_timesort"),
        "notifications": available.contains("message_popup_get_popup_notifications"),
        "assignments": available.contains("mod_assign_get_assignments"),
        "submission_status": available.contains("mod_assign_get_submission_status"),
        "announcements": available.contains("core_course_get_contents") && available.contains("mod_forum_get_forum_discussions_paginated"),
        "messages": available.contains("core_message_get_conversations"),
        "grades": available.contains("gradereport_user_get_grade_items"),
        "resources": available.contains("core_course_get_contents")
    })
}
fn safe_site(site: &Value) -> Value {
    json!({ "site_name": site.get("sitename"), "student_name": site.get("fullname"), "user_id": site.get("userid"), "site_url": LMS_ORIGIN })
}
fn course_summary(course: Value) -> Value {
    json!({ "id": course.get("id"), "name": course.get("fullname").or_else(|| course.get("displayname")).unwrap_or(&Value::String("Course".to_owned())), "short_name": course.get("shortname"), })
}
fn timestamp_is_today(value: Option<&str>) -> bool {
    let Some(value) = value else { return false };
    let Ok(timestamp) = OffsetDateTime::parse(value, &Rfc3339) else {
        return false;
    };
    timestamp.date() == OffsetDateTime::now_utc().date()
}
fn destination(value: &Value) -> String {
    value
        .get("url")
        .or_else(|| value.get("contexturl"))
        .or_else(|| value.get("fileurl"))
        .or_else(|| value.get("fileurl"))
        .or_else(|| value.get("contenturl"))
        .and_then(Value::as_str)
        .and_then(|candidate| Url::parse(candidate).ok())
        .filter(|url| url.origin().ascii_serialization() == LMS_ORIGIN)
        .map(|url| {
            let mut destination = url.path().to_owned();
            if let Some(query) = url.query() {
                destination.push('?');
                destination.push_str(query);
            }
            destination
        })
        .unwrap_or_default()
}
fn item(
    id: Value,
    kind: &str,
    title: Value,
    course_id: Value,
    course_name: Value,
    timestamp: Value,
    destination_value: String,
) -> Value {
    json!({ "id": id, "kind": kind, "title": title, "course_id": course_id, "course_name": course_name, "timestamp": timestamp, "destination": destination_value })
}
fn with_section(mut item: Value, section: &str) -> Value {
    item.as_object_mut()
        .expect("dashboard item object")
        .insert("section".to_owned(), Value::String(section.to_owned()));
    item
}
fn event_item(event: &Value) -> Value {
    item(
        event.get("id").cloned().unwrap_or(Value::Null),
        "assignment",
        event
            .get("name")
            .cloned()
            .unwrap_or(Value::String("Due item".to_owned())),
        event.get("courseid").cloned().unwrap_or(Value::Null),
        event
            .get("coursefullname")
            .cloned()
            .unwrap_or(Value::String("Course".to_owned())),
        event
            .get("timestart")
            .map(timestamp_value)
            .unwrap_or(Value::Null),
        destination(event),
    )
}
fn notification_item(notification: &Value) -> Value {
    let mut result = item(
        notification.get("id").cloned().unwrap_or(Value::Null),
        "notification",
        notification
            .get("subject")
            .or_else(|| notification.get("title"))
            .cloned()
            .unwrap_or(Value::String("LMS notification".to_owned())),
        Value::Null,
        notification
            .get("contextname")
            .cloned()
            .unwrap_or(Value::String("Course".to_owned())),
        Value::Null,
        destination(notification),
    );
    let is_unread = notification
        .get("read")
        .and_then(Value::as_i64)
        .map(|read| read == 0)
        .or_else(|| {
            notification
                .get("isread")
                .and_then(Value::as_bool)
                .map(|read| !read)
        })
        .unwrap_or(true);
    if let Some(object) = result.as_object_mut() {
        object.insert("is_unread".to_owned(), Value::Bool(is_unread));
    }
    result
}
fn message_item(message: &Value) -> Value {
    item(
        message.get("id").cloned().unwrap_or(Value::Null),
        "message",
        message
            .get("name")
            .cloned()
            .unwrap_or(Value::String("Recent message".to_owned())),
        Value::Null,
        Value::String("Messages".to_owned()),
        message
            .get("timemodified")
            .map(timestamp_value)
            .unwrap_or(Value::Null),
        format!(
            "/message/index.php?conversationid={}",
            message
                .get("id")
                .and_then(Value::as_i64)
                .unwrap_or_default()
        ),
    )
}
fn assignment_items(value: &Value) -> Vec<Value> {
    let mut items = Vec::new();
    for course in value
        .get("courses")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        for assignment in course
            .get("assignments")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let module_id = assignment
                .get("cmid")
                .or_else(|| assignment.get("id"))
                .and_then(Value::as_i64)
                .unwrap_or_default();
            items.push(item(
                assignment.get("id").cloned().unwrap_or(Value::Null),
                "assignment",
                assignment
                    .get("name")
                    .cloned()
                    .unwrap_or(Value::String("Assignment".to_owned())),
                course.get("id").cloned().unwrap_or(Value::Null),
                course
                    .get("fullname")
                    .cloned()
                    .unwrap_or(Value::String("Course".to_owned())),
                assignment
                    .get("duedate")
                    .map(timestamp_value)
                    .unwrap_or(Value::Null),
                format!("/mod/assign/view.php?id={module_id}"),
            ));
        }
    }
    items
}
fn submission_status(value: &Value) -> String {
    let status = value
        .get("lastattempt")
        .and_then(|value| value.get("submission"))
        .or_else(|| value.get("submission"));
    let status_name = status
        .and_then(|value| value.get("status"))
        .and_then(Value::as_str)
        .unwrap_or("");
    let reopened = value
        .get("feedback")
        .and_then(|value| value.get("grade"))
        .and_then(Value::as_i64)
        .is_some_and(|grade| grade < 0);
    match status_name {
        "submitted" => "submitted",
        "new" | "noattempt" | "" if reopened => "reopened",
        "new" | "noattempt" | "" => "not_submitted",
        "graded" => "graded",
        "reopened" => "reopened",
        _ => "unknown",
    }
    .to_owned()
}
fn forum_modules(value: &Value) -> Vec<Value> {
    value
        .as_array()
        .into_iter()
        .flatten()
        .flat_map(|section| {
            section
                .get("modules")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
        })
        .filter(|module| module.get("modname").and_then(Value::as_str) == Some("forum"))
        .cloned()
        .collect()
}
fn announcement_item(discussion: &Value, course: &Value, forum: &Value) -> Value {
    let destination_value = destination(discussion);
    let destination_value = if destination_value.is_empty() {
        let forum_id = forum
            .get("id")
            .or_else(|| forum.get("instance"))
            .and_then(Value::as_i64)
            .unwrap_or_default();
        format!("/mod/forum/view.php?id={forum_id}")
    } else {
        destination_value
    };
    let mut result = item(
        discussion.get("id").cloned().unwrap_or(Value::Null),
        "announcement",
        discussion
            .get("subject")
            .or_else(|| discussion.get("name"))
            .cloned()
            .unwrap_or(Value::String("Course announcement".to_owned())),
        course.get("id").cloned().unwrap_or(Value::Null),
        course
            .get("name")
            .cloned()
            .unwrap_or(Value::String("Course".to_owned())),
        discussion
            .get("timemodified")
            .or_else(|| discussion.get("created"))
            .map(timestamp_value)
            .unwrap_or(Value::Null),
        destination_value,
    );
    if let Some(excerpt) = discussion
        .get("message")
        .or_else(|| discussion.get("messagehtml"))
        .and_then(Value::as_str)
        .and_then(plain_feedback)
    {
        result
            .as_object_mut()
            .expect("announcement object")
            .insert("excerpt".to_owned(), Value::String(excerpt));
    }
    result.as_object_mut().expect("announcement object").insert(
        "section".to_owned(),
        Value::String("announcements".to_owned()),
    );
    result
}
fn resource_items(value: &Value, course: &Value) -> Vec<Value> {
    value
        .as_array()
        .into_iter()
        .flatten()
        .flat_map(|section| {
            section
                .get("modules")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
        })
        .filter(|module| {
            matches!(
                module.get("modname").and_then(Value::as_str),
                Some("resource") | Some("folder") | Some("url") | Some("page")
            )
        })
        .filter_map(|module| {
            let destination_value = module
                .get("contents")
                .and_then(Value::as_array)
                .and_then(|contents| contents.first())
                .map(destination)
                .filter(|value| !value.is_empty())
                .or_else(|| {
                    let url = destination(module);
                    (!url.is_empty()).then_some(url)
                })?;
            let mut result = item(
                module.get("id").cloned().unwrap_or(Value::Null),
                "resource",
                module
                    .get("name")
                    .cloned()
                    .unwrap_or(Value::String("Course resource".to_owned())),
                course.get("id").cloned().unwrap_or(Value::Null),
                course
                    .get("name")
                    .cloned()
                    .unwrap_or(Value::String("Course".to_owned())),
                Value::Null,
                destination_value,
            );
            let object = result.as_object_mut().expect("resource object");
            object.insert(
                "resource_kind".to_owned(),
                module
                    .get("modname")
                    .cloned()
                    .unwrap_or(Value::String("resource".to_owned())),
            );
            object.insert("section".to_owned(), Value::String("resources".to_owned()));
            Some(result)
        })
        .collect()
}
fn published_grade_items(value: &Value, course: &Value) -> Vec<Value> {
    value.get("usergrades").and_then(Value::as_array).and_then(|items| items.first()).and_then(|grade| grade.get("gradeitems")).and_then(Value::as_array).into_iter().flatten().filter(|grade| grade.get("hidden").and_then(Value::as_i64).unwrap_or(0) == 0).map(|grade| json!({ "id": grade.get("id"), "kind": "grade", "title": grade.get("itemname").cloned().unwrap_or(Value::String("Published grade".to_owned())), "course_id": course.get("id"), "course_name": course.get("name"), "timestamp": grade.get("gradedategraded").map(timestamp_value).unwrap_or(Value::Null), "destination": "", "is_total": grade.get("itemtype").and_then(Value::as_str) == Some("course"), "published_total": grade.get("gradeformatted") })).collect()
}
fn course_grade_items(value: &Value, course: &Value) -> Vec<Value> {
    value
        .get("usergrades")
        .and_then(Value::as_array)
        .and_then(|items| items.first())
        .and_then(|grade| grade.get("gradeitems"))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|grade| grade.get("hidden").and_then(Value::as_i64).unwrap_or(0) == 0)
        .map(|grade| {
            let course_id = course.get("id").and_then(Value::as_i64).unwrap_or_default();
            json!({
                "id": grade.get("id"),
                "title": grade.get("itemname").cloned().unwrap_or(Value::String("Published grade".to_owned())),
                "published_grade": grade.get("gradeformatted"),
                "feedback": grade.get("feedback").and_then(Value::as_str).and_then(plain_feedback),
                "timestamp": grade.get("gradedategraded").map(timestamp_value).unwrap_or(Value::Null),
                "destination": format!("/grade/report/user/index.php?id={course_id}"),
                "is_total": grade.get("itemtype").and_then(Value::as_str) == Some("course")
            })
        })
        .collect()
}
fn plain_feedback(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    let text = if trimmed.contains('<') && trimmed.contains('>') {
        html2text::config::plain_no_decorate()
            .string_from_read(trimmed.as_bytes(), 80)
            .ok()?
    } else {
        trimmed.to_owned()
    };
    let text = text.trim();
    (!text.is_empty()).then(|| text.chars().take(2_000).collect())
}
fn timestamp_value(value: &Value) -> Value {
    value
        .as_i64()
        .and_then(format_unix_timestamp)
        .map(Value::String)
        .unwrap_or_else(|| value.clone())
}
fn rfc3339_now() -> String {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_default()
}
fn unix_now() -> i64 {
    OffsetDateTime::now_utc().unix_timestamp()
}
fn format_unix_timestamp(seconds: i64) -> Option<String> {
    OffsetDateTime::from_unix_timestamp(seconds)
        .ok()?
        .format(&Rfc3339)
        .ok()
}
fn value_identifier(value: &Value) -> String {
    value
        .as_str()
        .map(str::to_owned)
        .unwrap_or_else(|| value.to_string())
}
fn section_failure(section: &str, error: &CoreError) -> String {
    format!("{section}: {}", redact(&error.to_string()))
}

pub fn redact(value: &str) -> String {
    let mut output = value.to_owned();
    for key in ["token", "wstoken", "password"] {
        if let Some(index) = output.to_ascii_lowercase().find(key) {
            let end = output[index..]
                .find(['&', ' ', '\n', '"'])
                .map(|offset| index + offset)
                .unwrap_or(output.len());
            output.replace_range(index..end, "[REDACTED]");
        }
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;
    use wiremock::{
        Mock, MockServer, ResponseTemplate,
        matchers::{method, path},
    };

    #[tokio::test]
    async fn password_exchange_returns_token_without_echoing_password() {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/login/token.php"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({"token":"test-token"})))
            .mount(&server)
            .await;
        let client = MoodleClient::for_test(Url::parse(&server.uri()).unwrap()).unwrap();
        let result = client
            .authenticate_with_password("alex", "secret-password")
            .await
            .unwrap();
        assert_eq!(result, json!({"token":"test-token"}));
    }

    #[test]
    fn rejects_non_lpu_origin() {
        assert!(MoodleClient::production().is_ok());
        assert!(MoodleClient::new(Url::parse("https://example.edu").unwrap(), false).is_err());
    }
    #[test]
    fn redacts_secret_fragments() {
        let value = redact("request token=abc123 password=hello");
        assert!(!value.contains("abc123"));
        assert!(!value.contains("hello"));
    }
    #[test]
    fn rejects_cross_origin_destination() {
        let client = MoodleClient::production().unwrap();
        assert!(client.resolve_destination("https://example.edu").is_err());
    }
    #[test]
    fn synthetic_site_fixture_exposes_only_advertised_capabilities() {
        let fixture: Value =
            serde_json::from_str(include_str!("../tests/fixtures/site-info.json")).unwrap();
        let available = capabilities(&fixture);
        assert!(available.contains("core_enrol_get_users_courses"));
        assert!(!available.contains("mod_assign_save_submission"));
    }
    #[test]
    fn course_grades_hide_private_items_and_flatten_feedback() {
        let fixture: Value =
            serde_json::from_str(include_str!("../tests/fixtures/grades.json")).unwrap();
        let course = json!({ "id": 12, "name": "Understanding the Self" });
        let grades = course_grade_items(&fixture, &course);
        assert_eq!(grades.len(), 2);
        assert_eq!(grades[0]["published_grade"], "1.50");
        assert_eq!(
            grades[0]["feedback"],
            "Clear argument and strong references."
        );
        assert!(grades.iter().all(|item| item["title"] != "Hidden activity"));
    }
    #[test]
    fn dashboard_sections_allow_only_read_only_sections() {
        let sections = normalize_sections(Some(&[
            Value::String("resources".to_owned()),
            Value::String("schedule".to_owned()),
        ]))
        .unwrap();
        assert!(sections.contains("resources"));
        assert!(sections.contains("schedule"));
        assert!(normalize_sections(Some(&[Value::String("write_grade".to_owned())])).is_err());
    }
    #[test]
    fn submission_status_has_read_only_normalization() {
        assert_eq!(
            submission_status(&json!({ "submission": { "status": "submitted" } })),
            "submitted"
        );
        assert_eq!(
            submission_status(&json!({ "submission": { "status": "new" } })),
            "not_submitted"
        );
        assert_eq!(
            submission_status(&json!({ "submission": { "status": "reopened" } })),
            "reopened"
        );
    }
    #[test]
    fn resources_drop_cross_origin_urls() {
        let course = json!({ "id": 12, "name": "History" });
        let contents = json!([{ "modules": [
            { "id": 1, "modname": "resource", "name": "Safe", "contents": [{ "fileurl": "https://lms.lpucavite.edu.ph/pluginfile.php/1/doc.pdf" }] },
            { "id": 2, "modname": "resource", "name": "Unsafe", "contents": [{ "fileurl": "https://example.edu/doc.pdf" }] }
        ] }]);
        let items = resource_items(&contents, &course);
        assert_eq!(items.len(), 1);
        assert_eq!(items[0]["title"], "Safe");
    }
}
