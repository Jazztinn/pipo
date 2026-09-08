import { createHmac } from "node:crypto";
import { hasRedisConfiguration, redisPipeline } from "../lib/redis.js";

const MAX_MESSAGE_LENGTH = 2000;
const MAX_BODY_BYTES = 4 * 1024;
const RATE_LIMIT = 3;
const DEFAULT_RECIPIENT = "legaspijazztinnkyle@gmail.com";

function requestTooLarge(request) {
  const length = Number(request.headers?.["content-length"] ?? 0);
  if (Number.isFinite(length) && length > MAX_BODY_BYTES) return true;
  if (typeof request.body === "string") return Buffer.byteLength(request.body, "utf8") > MAX_BODY_BYTES;
  try {
    return request.body != null && Buffer.byteLength(JSON.stringify(request.body), "utf8") > MAX_BODY_BYTES;
  } catch {
    return true;
  }
}

export default async function handler(request, response) {
  if (request.method !== "POST") {
    response.setHeader("Allow", "POST");
    return response.status(405).json({ ok: false, error: "Method not allowed" });
  }

  if (requestTooLarge(request)) {
    return response.status(413).json({ ok: false, error: "Request too large" });
  }
  let payload;
  try {
    payload = typeof request.body === "string" ? JSON.parse(request.body) : request.body;
  } catch {
    return response.status(400).json({ ok: false, error: "Invalid request" });
  }

  // Hidden field is filled by unsophisticated bots. Pretend success so it is not retried.
  if (typeof payload?.website === "string" && payload.website.trim()) return response.status(200).json({ ok: true });
  const message = typeof payload?.message === "string" ? payload.message.trim() : "";
  if (!message || message.length > MAX_MESSAGE_LENGTH) {
    return response.status(400).json({ ok: false, error: "Invalid message" });
  }

  const apiKey = process.env.RESEND_API_KEY;
  const sender = process.env.FEEDBACK_FROM_EMAIL;
  if (!apiKey || !sender) {
    console.error("Feedback email configuration is incomplete");
    return response.status(503).json({ ok: false, error: "Feedback is not configured" });
  }

  try {
    await enforceRateLimit(request);
  } catch (error) {
    if (error.message === "Feedback rate limit reached") return response.status(429).json({ ok: false, error: "Please wait before sending more feedback" });
    // Do not reject a real message only because optional anti-abuse storage is down.
  }

  try {
    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: sender,
        to: [process.env.FEEDBACK_TO_EMAIL || DEFAULT_RECIPIENT],
        subject: "Anonymous Pipo feedback",
        text: message,
      }),
    });

    if (!resendResponse.ok) {
      console.error("Feedback email provider rejected request", resendResponse.status);
      return response.status(502).json({ ok: false, error: "Feedback delivery failed" });
    }

    return response.status(200).json({ ok: true });
  } catch (error) {
    console.error("Feedback email delivery failed", error);
    return response.status(502).json({ ok: false, error: "Feedback delivery failed" });
  }
}

async function enforceRateLimit(request) {
  if (!hasRedisConfiguration()) return;
  const salt = process.env.PIPO_ABUSE_SALT;
  if (!salt) return;
  const forwarded = request.headers?.["x-forwarded-for"] ?? "";
  const client = forwarded.split(",")[0].trim() || request.headers?.["x-real-ip"] || "unknown";
  const fingerprint = createHmac("sha256", salt).update(client).digest("hex");
  const bucket = `pipo:feedback:rate:${fingerprint}:${new Date().toISOString().slice(0, 13)}`;
  const [count] = await redisPipeline([["INCR", bucket], ["EXPIRE", bucket, "7200"]], { timeoutMs: 700 });
  if (Number(count) > RATE_LIMIT) throw new Error("Feedback rate limit reached");
}
