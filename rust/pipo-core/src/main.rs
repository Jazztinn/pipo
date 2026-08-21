use std::sync::Arc;

use pipo_core::{MoodleClient, PROTOCOL_VERSION, REQUEST_CAP_BYTES, Request, Response, handle};
use tokio::io::{self, AsyncBufReadExt, AsyncWriteExt, BufReader};

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
        let bytes_read = match input.read_until(b'\n', &mut line).await {
            Ok(bytes_read) => bytes_read,
            Err(_) => break,
        };
        if bytes_read == 0 {
            break;
        }
        let response = if line.len() > REQUEST_CAP_BYTES {
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
                Ok(request) => handle(request, &client).await,
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
