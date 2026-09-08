//! Read-only provider boundary. Production registry exposes Moodle only; Canvas
//! exists behind `cfg(test)` for fixture-contract testing until onboarding enables it.

use std::sync::Arc;
#[cfg(test)]
use std::{collections::HashSet, net::IpAddr};

use serde::{Deserialize, Serialize};
use serde_json::Value;
#[cfg(test)]
use serde_json::json;

use crate::{CoreError, MoodleClient};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct EntityID {
    pub source: String,
    pub remote_id: String,
}

macro_rules! normalized_entity {
    ($name:ident) => {
        #[derive(Clone, Debug, Serialize, Deserialize)]
        pub struct $name {
            pub id: EntityID,
            pub title: String,
            #[serde(default)]
            pub data: Value,
        }
    };
}

normalized_entity!(Course);
normalized_entity!(Assignment);
normalized_entity!(Announcement);
normalized_entity!(Grade);
normalized_entity!(Message);
normalized_entity!(Resource);
normalized_entity!(CalendarEvent);

/// Provider methods return the established v3 snapshot shape while callers migrate
/// to the normalized entities above. No provider receives an arbitrary origin.
pub trait LMSProvider: Send + Sync {
    fn source(&self) -> &'static str;
    fn authenticate_token(
        &self,
        token: &str,
    ) -> impl std::future::Future<Output = Result<Value, CoreError>> + Send;
    fn capabilities(
        &self,
        token: &str,
    ) -> impl std::future::Future<Output = Result<Value, CoreError>> + Send;
    fn courses(
        &self,
        token: &str,
    ) -> impl std::future::Future<Output = Result<Value, CoreError>> + Send;
    fn fetch_sections(
        &self,
        token: &str,
        sections: Option<&[Value]>,
        day_start: Option<i64>,
        day_end: Option<i64>,
    ) -> impl std::future::Future<Output = Result<Value, CoreError>> + Send;
    fn load_course(
        &self,
        token: &str,
        course_id: i64,
    ) -> impl std::future::Future<Output = Result<Value, CoreError>> + Send;
    fn resolve_destination(&self, destination: &str) -> Result<Value, CoreError>;
}

#[derive(Clone)]
pub struct MoodleProvider {
    client: Arc<MoodleClient>,
}

impl MoodleProvider {
    pub fn new(client: Arc<MoodleClient>) -> Self {
        Self { client }
    }
}

impl LMSProvider for MoodleProvider {
    fn source(&self) -> &'static str {
        "moodle"
    }
    async fn authenticate_token(&self, token: &str) -> Result<Value, CoreError> {
        self.client.authenticate_with_token(token).await
    }
    async fn capabilities(&self, token: &str) -> Result<Value, CoreError> {
        self.client.discover_capabilities(token).await
    }
    async fn courses(&self, token: &str) -> Result<Value, CoreError> {
        let (_, courses) = self.client.context_for_provider(token).await?;
        Ok(Value::Array(courses))
    }
    async fn fetch_sections(
        &self,
        token: &str,
        sections: Option<&[Value]>,
        day_start: Option<i64>,
        day_end: Option<i64>,
    ) -> Result<Value, CoreError> {
        self.client
            .refresh_dashboard(token, sections, day_start, day_end)
            .await
    }
    async fn load_course(&self, token: &str, course_id: i64) -> Result<Value, CoreError> {
        self.client.load_course(token, course_id).await
    }
    fn resolve_destination(&self, destination: &str) -> Result<Value, CoreError> {
        self.client.resolve_destination(destination)
    }
}

#[cfg(test)]
#[derive(Clone)]
pub struct CanvasProvider {
    http: reqwest::Client,
    origin: url::Url,
    cooldown_until: Arc<std::sync::Mutex<Option<std::time::Instant>>>,
    deadline: Arc<std::sync::Mutex<Option<std::time::Instant>>>,
}

#[cfg(test)]
impl CanvasProvider {
    pub fn for_fixture(origin: url::Url) -> Result<Self, CoreError> {
        let loopback = origin.host_str().is_some_and(|host| {
            host.eq_ignore_ascii_case("localhost")
                || host
                    .parse::<IpAddr>()
                    .is_ok_and(|address| address.is_loopback())
        });
        if (origin.scheme() != "http" && origin.scheme() != "https") || !loopback {
            return Err(CoreError::Origin);
        }
        let fixed = origin.origin().ascii_serialization();
        let redirect = reqwest::redirect::Policy::custom(move |attempt| {
            if attempt.url().origin().ascii_serialization() == fixed {
                attempt.follow()
            } else {
                attempt.stop()
            }
        });
        Ok(Self {
            http: reqwest::Client::builder()
                .redirect(redirect)
                .build()
                .map_err(CoreError::from)?,
            origin,
            cooldown_until: Arc::new(std::sync::Mutex::new(None)),
            deadline: Arc::new(std::sync::Mutex::new(None)),
        })
    }

    fn begin(&self) {
        *self.deadline.lock().expect("deadline") =
            Some(std::time::Instant::now() + std::time::Duration::from_secs(20));
    }

    async fn within_deadline<T>(
        &self,
        future: impl std::future::Future<Output = Result<T, reqwest::Error>>,
    ) -> Result<T, CoreError> {
        let deadline = *self.deadline.lock().expect("deadline");
        match deadline {
            Some(deadline) if deadline <= std::time::Instant::now() => Err(CoreError::Timeout),
            Some(deadline) => {
                tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), future)
                    .await
                    .map_err(|_| CoreError::Timeout)?
                    .map_err(CoreError::from)
            }
            None => future.await.map_err(CoreError::from),
        }
    }

    async fn get(&self, token: &str, url: url::Url) -> Result<(Value, Option<String>), CoreError> {
        if url.origin() != self.origin.origin() {
            return Err(CoreError::Origin);
        }
        let cooldown = *self.cooldown_until.lock().expect("cooldown");
        if let Some(until) = cooldown
            && let Some(wait) = until.checked_duration_since(std::time::Instant::now())
        {
            if self
                .deadline
                .lock()
                .expect("deadline")
                .is_some_and(|deadline| std::time::Instant::now() + wait >= deadline)
            {
                return Err(CoreError::Timeout);
            }
            tokio::time::sleep(wait).await;
        }
        let response = self
            .within_deadline(self.http.get(url).bearer_auth(token).send())
            .await?;
        let status = response.status();
        if status.as_u16() == 401 {
            return Err(CoreError::Authentication("Canvas token expired".to_owned()));
        }
        if status.as_u16() == 403 {
            return Err(CoreError::AccessDenied);
        }
        if status.as_u16() == 429 {
            if let Some(delay) = crate::retry_after_delay(response.headers()) {
                *self.cooldown_until.lock().expect("cooldown") =
                    Some(std::time::Instant::now() + delay);
            }
            return Err(CoreError::RateLimited);
        }
        if status.as_u16() == 404 {
            return Err(CoreError::Unsupported(
                "Canvas endpoint unavailable".to_owned(),
            ));
        }
        if !status.is_success() {
            return Err(CoreError::Network(format!("Canvas returned HTTP {status}")));
        }
        let next = response
            .headers()
            .get(reqwest::header::LINK)
            .and_then(|value| value.to_str().ok())
            .and_then(canvas_next_link);
        let value = self.within_deadline(response.json()).await?;
        Ok((value, next))
    }

    async fn paged(&self, token: &str, path: &str) -> Result<Vec<Value>, CoreError> {
        let mut next = Some(self.origin.join(path).map_err(|_| CoreError::Origin)?);
        let mut output = Vec::new();
        let mut visited = HashSet::new();
        let mut attempts = 0_usize;
        while let Some(url) = next.take() {
            attempts += 1;
            if attempts > 32 {
                return Err(CoreError::Response(
                    "Canvas pagination exceeded 32 pages".to_owned(),
                ));
            }
            if !visited.insert(url.to_string()) {
                return Err(CoreError::Response("Canvas pagination cycle".to_owned()));
            }
            let (value, link) = self.get(token, url).await?;
            output.extend(
                value.as_array().cloned().ok_or_else(|| {
                    CoreError::Response("expected Canvas array response".to_owned())
                })?,
            );
            next = link
                .map(|link| {
                    url::Url::parse(&link)
                        .map_err(|_| CoreError::Response("invalid Canvas Link header".to_owned()))
                })
                .transpose()?;
            if next
                .as_ref()
                .is_some_and(|url| url.origin() != self.origin.origin())
            {
                return Err(CoreError::Origin);
            }
        }
        Ok(output)
    }

    async fn optional_paged(&self, token: &str, path: &str) -> Result<Vec<Value>, CoreError> {
        match self.paged(token, path).await {
            Ok(value) => Ok(value),
            Err(CoreError::Unsupported(_)) => Ok(Vec::new()),
            Err(error) => Err(error),
        }
    }
}

#[cfg(test)]
impl LMSProvider for CanvasProvider {
    fn source(&self) -> &'static str {
        "canvas"
    }
    async fn authenticate_token(&self, token: &str) -> Result<Value, CoreError> {
        self.begin();
        let (user, _) = self
            .get(
                token,
                self.origin
                    .join("/api/v1/users/self")
                    .map_err(|_| CoreError::Origin)?,
            )
            .await?;
        Ok(
            json!({ "account_id": user.get("id"), "site": { "student_name": user.get("name") }, "source": "canvas" }),
        )
    }
    async fn capabilities(&self, _token: &str) -> Result<Value, CoreError> {
        Ok(
            json!({ "source": "canvas", "read_only": true, "supported": { "assignments": true, "grades": true, "announcements": true, "resources": true, "schedule": true, "messages": true } }),
        )
    }
    async fn courses(&self, token: &str) -> Result<Value, CoreError> {
        self.begin();
        Ok(Value::Array(
            self.paged(token, "/api/v1/courses?enrollment_state=active")
                .await?,
        ))
    }
    async fn fetch_sections(
        &self,
        token: &str,
        _sections: Option<&[Value]>,
        _day_start: Option<i64>,
        _day_end: Option<i64>,
    ) -> Result<Value, CoreError> {
        self.begin();
        let courses = self
            .paged(token, "/api/v1/courses?enrollment_state=active")
            .await?;
        let assignments = self
            .optional_paged(token, "/api/v1/users/self/assignments?include[]=submission")
            .await?;
        let grades = self
            .optional_paged(token, "/api/v1/users/self/enrollments?include[]=grades")
            .await?;
        let announcements = self
            .optional_paged(token, "/api/v1/announcements?context_codes[]=user")
            .await?;
        let calendar = self
            .optional_paged(token, "/api/v1/calendar_events")
            .await?;
        let messages = self.optional_paged(token, "/api/v1/conversations").await?;
        let mut resources = Vec::new();
        for course in &courses {
            if let Some(id) = course.get("id").and_then(Value::as_i64) {
                resources.extend(
                    self.optional_paged(token, &format!("/api/v1/courses/{id}/files"))
                        .await?,
                );
            }
        }
        Ok(
            json!({ "version": crate::SNAPSHOT_SCHEMA_VERSION, "source": "canvas", "courses": courses, "sections": { "new_assignments": assignments, "grade_feedback": grades, "messages": messages, "due_soon": calendar, "notifications": [] }, "announcements": announcements, "resources": resources, "schedule": [], "section_results": {} }),
        )
    }
    async fn load_course(&self, token: &str, course_id: i64) -> Result<Value, CoreError> {
        self.begin();
        let course = self
            .get(
                token,
                self.origin
                    .join(&format!("/api/v1/courses/{course_id}"))
                    .map_err(|_| CoreError::Origin)?,
            )
            .await?
            .0;
        let assignments = self
            .optional_paged(
                token,
                &format!("/api/v1/courses/{course_id}/assignments?include[]=submission"),
            )
            .await?;
        let grades = self
            .paged(
                token,
                &format!("/api/v1/courses/{course_id}/enrollments?user_id=self"),
            )
            .await?;
        let announcements = self
            .optional_paged(
                token,
                &format!("/api/v1/announcements?context_codes[]=course_{course_id}"),
            )
            .await?;
        let resources = self
            .optional_paged(token, &format!("/api/v1/courses/{course_id}/files"))
            .await?;
        Ok(
            json!({ "version": crate::SNAPSHOT_SCHEMA_VERSION, "source": "canvas", "course": course, "assignments": assignments, "grades": grades, "announcements": announcements, "resources": resources, "section_results": {} }),
        )
    }
    fn resolve_destination(&self, destination: &str) -> Result<Value, CoreError> {
        let url = self
            .origin
            .join(destination)
            .map_err(|_| CoreError::Origin)?;
        if url.origin() != self.origin.origin() {
            return Err(CoreError::Origin);
        }
        Ok(json!({ "url": url.to_string() }))
    }
}

#[cfg(test)]
pub(crate) fn canvas_next_link(header: &str) -> Option<String> {
    header.split(',').find_map(|part| {
        if part.contains("rel=\"next\"") || part.contains("rel=next") {
            part.split('<').nth(1)?.split('>').next().map(str::to_owned)
        } else {
            None
        }
    })
}
