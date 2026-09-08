import { createHmac, timingSafeEqual } from "node:crypto";
import { hasRedisConfiguration, redisPipeline } from "../lib/redis.js";

const INSTALL_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const VERSION = new Set(["0.5.3"]);
const EVENT_TYPES = new Set(["launch", "heartbeat"]);
const ACTIVE_DAYS = 30;
const RETENTION_DAYS = 31;
const DAY_TTL_SECONDS = 60 * 60 * 24 * RETENTION_DAYS;
const MAX_BODY_BYTES = 1024;
const RATE_LIMIT = 24;

function today() {
  return new Date().toISOString().slice(0, 10);
}

function dayKeys(days) {
  const now = new Date();
  return Array.from({ length: days }, (_, index) => {
    const date = new Date(now);
    date.setUTCDate(now.getUTCDate() - index);
    return `pipo:usage:active:${date.toISOString().slice(0, 10)}`;
  });
}

function hashInstallID(installID) {
  const salt = process.env.PIPO_USAGE_SALT;
  if (!salt) throw new Error("PIPO_USAGE_SALT is missing");
  return createHmac("sha256", salt).update(installID).digest("hex");
}

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

function providedToken(request) {
  const header = request.headers?.authorization ?? "";
  return header.startsWith("Bearer ") ? header.slice(7) : "";
}

function tokenMatches(request) {
  const expected = process.env.PIPO_STATS_TOKEN ?? "";
  const provided = providedToken(request);
  if (!expected || !provided) return false;
  const expectedBytes = Buffer.from(expected);
  const providedBytes = Buffer.from(provided);
  return expectedBytes.length === providedBytes.length && timingSafeEqual(expectedBytes, providedBytes);
}

function json(response, status, body) {
  response.status(status).json(body);
}

async function recordUsage(payload) {
  const installHash = hashInstallID(payload.install_id);
  const day = today();
  const commands = [
    ["SADD", `pipo:usage:active:${day}`, installHash],
    ["EXPIRE", `pipo:usage:active:${day}`, String(DAY_TTL_SECONDS)],
    ["INCR", `pipo:usage:events:${installHash}:${day}`],
    ["EXPIRE", `pipo:usage:events:${installHash}:${day}`, String(DAY_TTL_SECONDS)],
  ];
  if (payload.version && VERSION.has(payload.version)) {
    commands.push(["SADD", `pipo:usage:versions:${day}`, payload.version]);
    commands.push(["EXPIRE", `pipo:usage:versions:${day}`, String(DAY_TTL_SECONDS)]);
    commands.push(["SADD", `pipo:usage:active:${day}:${payload.version}`, installHash]);
    commands.push(["EXPIRE", `pipo:usage:active:${day}:${payload.version}`, String(DAY_TTL_SECONDS)]);
  }
  const results = await redisPipeline(commands);
  if (Number(results[2]) > RATE_LIMIT) throw new Error("Usage rate limit reached");
}

async function readSummary() {
  const dailyKeys = dayKeys(ACTIVE_DAYS);
  const unionKey = `pipo:usage:report:${Date.now()}`;
  const versionKeys = dailyKeys.map((key) => key.replace("pipo:usage:active:", "pipo:usage:versions:"));
  const [activeToday, downloadCount, downloadToday, versions] = await redisPipeline([
    ["SCARD", dailyKeys[0]],
    ["GET", "pipo:downloads:total"],
    ["GET", `pipo:downloads:${today()}`],
    ["SUNION", ...versionKeys],
  ]);
  const versionCounts = versions?.length ? await Promise.all((versions ?? []).map(async (version) => {
    const key = `pipo:usage:report:${version}:${Date.now()}`;
    await redisPipeline([["SUNIONSTORE", key, ...dailyKeys.map((daily) => `${daily}:${version}`)], ["EXPIRE", key, "60"]]);
    return (await redisPipeline([["SCARD", key]]))[0];
  })) : [];
  await redisPipeline([
    ["SUNIONSTORE", unionKey, ...dailyKeys],
    ["EXPIRE", unionKey, "60"],
  ]);
  const [activeLast30Days] = await redisPipeline([["SCARD", unionKey]]);
  return {
    generated_at: new Date().toISOString(),
    downloads: {
      starts_total: Number(downloadCount ?? 0),
      starts_today: Number(downloadToday ?? 0),
    },
    installs: {
      observed_last_30_days: Number(activeLast30Days ?? 0),
    },
    active: {
      today: Number(activeToday ?? 0),
      last_30_days: Number(activeLast30Days ?? 0),
    },
    active_by_version: Object.fromEntries(
      (versions ?? []).map((version, index) => [version, Number(versionCounts[index] ?? 0)]),
    ),
    definitions: {
      download: "A website download request that reached the redirect endpoint; it does not prove the DMG finished downloading.",
      install: "A unique anonymous install ID observed during the trailing 30 UTC days.",
      active_today: "A unique install that sent a launch or heartbeat event during the current UTC day.",
      active_last_30_days: "A unique install seen during the trailing 30 UTC days.",
    },
  };
}

export default async function handler(request, response) {
  response.setHeader("Cache-Control", "no-store");

  if (request.method === "POST") {
    if (!hasRedisConfiguration() || !process.env.PIPO_USAGE_SALT) {
      return json(response, 503, { ok: false, error: "Usage tracking is not configured" });
    }

    if (requestTooLarge(request)) return json(response, 413, { ok: false, error: "Request too large" });
    let payload;
    try {
      payload = typeof request.body === "string" ? JSON.parse(request.body) : request.body;
    } catch {
      return json(response, 400, { ok: false, error: "Invalid request" });
    }

    if (
      !EVENT_TYPES.has(payload?.event) ||
      !INSTALL_ID.test(payload?.install_id ?? "") ||
      !VERSION.has(payload?.version) ||
      payload?.platform !== "macos"
    ) {
      return json(response, 400, { ok: false, error: "Invalid usage event" });
    }

    try {
      await recordUsage(payload);
      return json(response, 202, { ok: true });
    } catch (error) {
      if (error.message === "Usage rate limit reached") return json(response, 429, { ok: false, error: "Usage rate limit reached" });
      console.error("Pipo usage tracking failed", error.name);
      return json(response, 503, { ok: false, error: "Usage tracking unavailable" });
    }
  }

  if (request.method === "GET") {
    if (!tokenMatches(request)) return json(response, 401, { ok: false, error: "Unauthorized" });
    if (!hasRedisConfiguration()) return json(response, 503, { ok: false, error: "Usage tracking is not configured" });

    try {
      return json(response, 200, await readSummary());
    } catch (error) {
      console.error("Pipo usage report failed", error.message);
      return json(response, 503, { ok: false, error: "Usage report unavailable" });
    }
  }

  response.setHeader("Allow", "GET, POST");
  return json(response, 405, { ok: false, error: "Method not allowed" });
}
