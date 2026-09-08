use std::sync::Arc;
use std::time::Duration;

use pipo_core::{MoodleClient, PROTOCOL_VERSION, REQUEST_CAP_BYTES, Request, Response, handle};
use tokio::io::{self, AsyncBufRead, AsyncBufReadExt, AsyncWriteExt, BufReader};

/// Reads one JSON line without allowing an unbounded allocation for hostile input.
async fn read_line_limited<R: AsyncBufRead + Unpin>(
    input: &mut R,
    line: &mut Vec<u8>,
) -> io::Result<Option<bool>> {
    let mut overflow = false;
    loop {
        let buffer = input.fill_buf().await?;
        if buffer.is_empty() {
            return Ok((!line.is_empty() || overflow).then_some(overflow));
        }
        let consumed = buffer
            .iter()
            .position(|byte| *byte == b'\n')
            .map(|position| position + 1)
            .unwrap_or(buffer.len());
        if !overflow && line.len().saturating_add(consumed) <= REQUEST_CAP_BYTES {
            line.extend_from_slice(&buffer[..consumed]);
        } else {
            overflow = true;
        }
        let complete = buffer[..consumed].last() == Some(&b'\n');
        input.consume(consumed);
        if complete {
            return Ok(Some(overflow));
        }
    }
}

#[tokio::main]
async fn main() {
    let client = match MoodleClient::production() {
        Ok(client) => Arc::new(client),
        Err(error) => {
            eprintln!(
                "pipo-core configuration error: {}",
                pipo_core::redact(&error.to_string())
            );
            std::process::exit(2);
        }
    };
    let mut input = BufReader::new(io::stdin());
    let mut output = io::stdout();
    loop {
        let mut line = Vec::new();
        let overflow = match read_line_limited(&mut input, &mut line).await {
            Ok(Some(overflow)) => overflow,
            Ok(None) => break,
            Err(_) => break,
        };
        let response = if overflow {
            Response {
                version: PROTOCOL_VERSION,
                id: String::new(),
                result: None,
                error: Some(pipo_core::ErrorEnvelope {
                    code: "invalid_input",
                    message: format!("request exceeds {REQUEST_CAP_BYTES} byte limit"),
                }),
            }
        } else {
            match serde_json::from_slice::<Request>(&line) {
                Ok(request) => {
                    let id = request.id.clone();
                    let timeout = match &request.method {
                        pipo_core::Method::RefreshDashboard => Duration::from_secs(50),
                        pipo_core::Method::LoadCourse => Duration::from_secs(30),
                        _ => Duration::from_secs(25),
                    };
                    match tokio::time::timeout(timeout, handle(request, &client)).await {
                        Ok(response) => response,
                        Err(_) => Response {
                            version: PROTOCOL_VERSION,
                            id,
                            result: None,
                            error: Some(pipo_core::ErrorEnvelope {
                                code: "timeout",
                                message: "The LMS took too long to respond. Try again shortly."
                                    .to_owned(),
                            }),
                        },
                    }
                }
                Err(error) => Response {
                    version: PROTOCOL_VERSION,
                    id: String::new(),
                    result: None,
                    error: Some(pipo_core::ErrorEnvelope {
                        code: "invalid_input",
                        message: pipo_core::redact(&format!("invalid JSON request: {error}")),
                    }),
                },
            }
        };
        if let Ok(encoded) = serde_json::to_string(&response) {
            let _ = output.write_all(encoded.as_bytes()).await;
            let _ = output.write_all(b"\n").await;
            let _ = output.flush().await;
        }
    }
}
