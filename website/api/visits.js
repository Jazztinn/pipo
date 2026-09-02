import { hasRedisConfiguration, redisPipeline } from "../lib/redis.js";

const INITIAL_VISITS = 82;
const VISITS_KEY = "pipo:website:visits";

function json(response, status, body) {
  response.status(status).json(body);
}

async function recordVisit() {
  const [initialized] = await redisPipeline([
    ["SETNX", VISITS_KEY, String(INITIAL_VISITS)],
  ]);

  if (Number(initialized) === 1) return INITIAL_VISITS;

  const [visits] = await redisPipeline([["INCR", VISITS_KEY]]);
  return Number(visits);
}

export default async function handler(request, response) {
  response.setHeader("Cache-Control", "no-store");

  if (request.method !== "POST") {
    response.setHeader("Allow", "POST");
    return json(response, 405, { ok: false, error: "Method not allowed" });
  }

  if (!hasRedisConfiguration()) {
    return json(response, 503, { ok: false, error: "Visit tracking is not configured" });
  }

  try {
    return json(response, 200, { ok: true, visits: await recordVisit() });
  } catch (error) {
    console.error("Pipo website visit tracking failed", error.message);
    return json(response, 503, { ok: false, error: "Visit tracking unavailable" });
  }
}
