import assert from "node:assert/strict";
import test from "node:test";

const usageHandler = (await import("../api/usage.js")).default;
const downloadHandler = (await import("../api/download.js")).default;
const feedbackHandler = (await import("../api/feedback.js")).default;

function response() {
  return {
    headers: {}, statusCode: 0, body: undefined, location: undefined,
    setHeader(name, value) { this.headers[name] = value; },
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
    redirect(code, location) { this.statusCode = code; this.location = location; return this; },
  };
}

function saveEnv() {
  const saved = { ...process.env };
  return () => {
    for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
    Object.assign(process.env, saved);
  };
}

test("usage rejects oversized and unknown-release events before Redis", async () => {
  const restore = saveEnv();
  process.env.UPSTASH_REDIS_REST_URL = "https://redis.test";
  process.env.UPSTASH_REDIS_REST_TOKEN = "token";
  process.env.PIPO_USAGE_SALT = "salt";
  const oldFetch = globalThis.fetch;
  globalThis.fetch = () => { throw new Error("Redis must not be called"); };
  try {
    let res = response();
    await usageHandler({ method: "POST", headers: { "content-length": "1025" } }, res);
    assert.equal(res.statusCode, 413);
    res = response();
    await usageHandler({ method: "POST", body: { event: "launch", install_id: "123e4567-e89b-42d3-a456-426614174000", platform: "macos", version: "9.9.9" } }, res);
    assert.equal(res.statusCode, 400);
    res = response();
    await usageHandler({ method: "POST", body: { message: "x".repeat(2048) } }, res);
    assert.equal(res.statusCode, 413);
  } finally { globalThis.fetch = oldFetch; restore(); }
});

test("download redirects when Redis telemetry stalls", async () => {
  const restore = saveEnv();
  process.env.UPSTASH_REDIS_REST_URL = "https://redis.test";
  process.env.UPSTASH_REDIS_REST_TOKEN = "token";
  const oldFetch = globalThis.fetch;
  globalThis.fetch = (_url, { signal }) => new Promise((_, reject) => signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError"))));
  try {
    const res = response();
    const start = Date.now();
    await downloadHandler({ method: "GET" }, res);
    assert.equal(res.statusCode, 302);
    assert.equal(res.location, "https://github.com/Jazztinn/pipo/releases/download/v0.5.3/Pipo-0.5.3-universal.dmg");
    assert.ok(Date.now() - start < 650);
  } finally { globalThis.fetch = oldFetch; restore(); }
});

test("feedback honeypot succeeds without email and oversized input is rejected", async () => {
  const restore = saveEnv();
  delete process.env.RESEND_API_KEY;
  delete process.env.FEEDBACK_FROM_EMAIL;
  try {
    let res = response();
    await feedbackHandler({ method: "POST", body: { message: "hello", website: "bot.example" } }, res);
    assert.equal(res.statusCode, 200);
    res = response();
    await feedbackHandler({ method: "POST", headers: { "content-length": "4097" } }, res);
    assert.equal(res.statusCode, 413);
    res = response();
    await feedbackHandler({ method: "POST", body: { message: "x".repeat(4096) } }, res);
    assert.equal(res.statusCode, 413);
  } finally { restore(); }
});
