const redisURL = () => process.env.UPSTASH_REDIS_REST_URL;
const redisToken = () => process.env.UPSTASH_REDIS_REST_TOKEN;

export function hasRedisConfiguration() {
  return Boolean(redisURL() && redisToken());
}

export async function redisPipeline(commands, { timeoutMs = 800 } = {}) {
  const url = redisURL();
  const token = redisToken();
  if (!url || !token) throw new Error("Redis configuration is incomplete");

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  let result;
  try {
    result = await fetch(`${url.replace(/\/$/, "")}/pipeline`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(commands),
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeout);
  }

  if (!result.ok) throw new Error(`Redis request failed (${result.status})`);
  const payload = await result.json();
  if (!Array.isArray(payload) || payload.some((item) => item?.error)) {
    throw new Error("Redis returned an invalid pipeline response");
  }
  return payload.map((item) => item.result);
}
