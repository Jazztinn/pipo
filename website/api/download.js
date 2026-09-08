import { hasRedisConfiguration, redisPipeline } from "../lib/redis.js";

const DOWNLOAD_TARGET = "/Pipo-0.5.3-universal.dmg";
const RELEASE_VERSION = "0.5.3";
const TELEMETRY_TIMEOUT_MS = 450;

function telemetry() {
  if (!hasRedisConfiguration()) return Promise.resolve();
  const day = new Date().toISOString().slice(0, 10);
  return redisPipeline([
    ["INCR", "pipo:downloads:total"],
    ["INCR", `pipo:downloads:${day}`],
    ["INCR", `pipo:downloads:version:${RELEASE_VERSION}`],
  ], { timeoutMs: TELEMETRY_TIMEOUT_MS });
}

export default async function handler(request, response) {
  if (request.method !== "GET") {
    response.setHeader("Allow", "GET");
    response.status(405).json({ ok: false, error: "Method not allowed" });
    return;
  }

  // Redirect remains available when telemetry is slow or unavailable.
  try { await telemetry(); } catch (error) { console.error("Pipo download tracking failed", error.name); }

  response.setHeader("Cache-Control", "no-store");
  response.redirect(302, DOWNLOAD_TARGET);
}
