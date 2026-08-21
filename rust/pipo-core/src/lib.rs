//! JSON-lines sidecar for Pipo. The Moodle request shape is adapted from
//! ALinuxPerson/openlms-mcp at c5a09e9f70d56def5e26acea425d1a7dfd514503.
//! Pipo intentionally exposes a small read-only subset and no network listener.

use std::{collections::HashSet, time::Duration};

use futures_util::StreamExt;
use reqwest::{Client, redirect};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use thiserror::Error;
use time::{OffsetDateTime, format_description::well_known::Rfc3339};
use url::Url;

pub const PROTOCOL_VERSION: u8 = 1;
pub const LMS_ORIGIN: &str = "https://lms.lpucavite.edu.ph";
pub const REQUEST_CAP_BYTES: usize = 2 * 1024 * 1024;
const RESPONSE_CAP_BYTES: usize = 2 * 1024 * 1024;
const TOKEN_RESPONSE_CAP_BYTES: usize = 256 * 1024;
const SERVICE: &str = "moodle_mobile_app";

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
        Ok(json!({ "site": safe_site(&site), "functions": functions, "read_only": true }))
    }

    pub async fn refresh_dashboard(&self, token: &str) -> Result<Value, CoreError> {
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
        let now = unix_now();
        let events = if capabilities.contains("core_calendar_get_action_events_by_timesort") {
            match self.call(
                token,
                "core_calendar_get_action_events_by_timesort",
                json!({ "timesortfrom": now, "timesortto": now + (7 * 24 * 60 * 60), "limitnum": 30 }),
            )
            .await {
                Ok(value) => value,
                Err(error) => {
                    failures.push(section_failure("Due soon", &error));
                    Value::Null
                }
            }
        } else {
            Value::Null
        };
        let due_soon = events
            .get("events")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .map(event_item)
            .collect::<Vec<_>>();
        let due_ids = due_soon
            .iter()
            .filter_map(|item| item.get("destination").and_then(Value::as_str))
            .collect::<HashSet<_>>();

        let notifications = if capabilities.contains("message_popup_get_popup_notifications") {
            match self
                .call(
                    token,
                    "message_popup_get_popup_notifications",
                    json!({ "limit": 20, "offset": 0 }),
                )
                .await
            {
                Ok(value) => value,
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

        let assignments = if capabilities.contains("mod_assign_get_assignments") {
            match self.call(token, "mod_assign_get_assignments", json!({ "courseids": courses.iter().filter_map(|course| course.get("id").and_then(Value::as_i64)).collect::<Vec<_>>() })).await {
                Ok(value) => value,
                Err(error) => {
                    failures.push(section_failure("Assignments", &error));
                    Value::Null
                }
            }
        } else {
            Value::Null
        };
        let assignment_items = assignment_items(&assignments);
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

        let messages = if capabilities.contains("core_message_get_conversations") {
            match self.call(token, "core_message_get_conversations", json!({ "userid": user_id, "limitfrom": 0, "limitnum": 10, "type": 0, "favourites": false })).await {
                Ok(value) => value,
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
        if capabilities.contains("gradereport_user_get_grade_items") {
            for course in courses {
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
                let published = published_grade_items(&grades, &course);
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
        } else {
            courses_with_grades = courses;
        }

        Ok(json!({
            "version": PROTOCOL_VERSION,
            "generated_at": rfc3339_now(),
            "site_name": site.get("sitename").and_then(Value::as_str).unwrap_or("LPU Cavite LMS"),
            "student_name": site.get("fullname").and_then(Value::as_str).unwrap_or(""),
            "sections": { "due_soon": due_soon, "notifications": notifications, "new_assignments": new_assignments, "messages": messages, "grade_feedback": grade_feedback },
            "assignment_ids": assignment_ids,
            "courses": courses_with_grades,
            "failures": failures
        }))
    }

    pub async fn load_course(&self, token: &str, course_id: i64) -> Result<Value, CoreError> {
        if course_id <= 0 {
            return Err(CoreError::Input("course_id must be positive".to_owned()));
        }
        self.call(
            token,
            "core_course_get_contents",
            json!({ "courseid": course_id }),
        )
        .await
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
                .refresh_dashboard(required_string(object, "token")?)
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
fn safe_site(site: &Value) -> Value {
    json!({ "site_name": site.get("sitename"), "student_name": site.get("fullname"), "user_id": site.get("userid"), "site_url": LMS_ORIGIN })
}
fn course_summary(course: Value) -> Value {
    json!({ "id": course.get("id"), "name": course.get("fullname").or_else(|| course.get("displayname")).unwrap_or(&Value::String("Course".to_owned())), "short_name": course.get("shortname"), })
}
fn destination(value: &Value) -> String {
    value
        .get("url")
        .or_else(|| value.get("contexturl"))
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
fn published_grade_items(value: &Value, course: &Value) -> Vec<Value> {
    value.get("usergrades").and_then(Value::as_array).and_then(|items| items.first()).and_then(|grade| grade.get("gradeitems")).and_then(Value::as_array).into_iter().flatten().filter(|grade| grade.get("hidden").and_then(Value::as_i64).unwrap_or(0) == 0).map(|grade| json!({ "id": grade.get("id"), "kind": "grade", "title": grade.get("itemname").cloned().unwrap_or(Value::String("Published grade".to_owned())), "course_id": course.get("id"), "course_name": course.get("name"), "timestamp": grade.get("gradedategraded").map(timestamp_value).unwrap_or(Value::Null), "destination": "", "is_total": grade.get("itemtype").and_then(Value::as_str) == Some("course"), "published_total": grade.get("gradeformatted") })).collect()
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
}
