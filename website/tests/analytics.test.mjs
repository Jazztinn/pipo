import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const mainJs = await readFile(new URL("../src/main.js", import.meta.url), "utf8");
const privacyHtml = await readFile(new URL("../privacy.html", import.meta.url), "utf8");
const usageApi = await readFile(new URL("../api/usage.js", import.meta.url), "utf8");
const visitsApi = await readFile(new URL("../api/visits.js", import.meta.url), "utf8");
const downloadApi = await readFile(new URL("../api/download.js", import.meta.url), "utf8");
const visitsHandler = (await import("../api/visits.js")).default;

test("website injects Vercel Web Analytics", () => {
  assert.match(mainJs, /import \{ inject \} from "@vercel\/analytics"/);
  assert.match(mainJs, /inject\(\);/);
});

test("privacy policy discloses analytics and feedback delivery", () => {
  assert.match(privacyHtml, /Vercel Web Analytics/);
  assert.match(privacyHtml, /Resend/);
  assert.match(privacyHtml, /random install ID/);
  assert.match(privacyHtml, /Upstash Redis/);
  assert.match(privacyHtml, /server-side counter shared across its domains and devices/);
  assert.doesNotMatch(privacyHtml, /visit count in your browser’s local storage/);
  assert.doesNotMatch(privacyHtml, /no analytics integration/);
});

test("usage routes separate download starts from anonymous app activity", () => {
  assert.match(downloadApi, /pipo:downloads:total/);
  assert.match(downloadApi, /response\.redirect\(302, DOWNLOAD_TARGET\)/);
  assert.match(usageApi, /observed_last_30_days/);
  assert.match(usageApi, /pipo:usage:active:/);
  assert.match(usageApi, /createHmac\("sha256"/);
  assert.match(usageApi, /PIPO_STATS_TOKEN/);
  assert.doesNotMatch(usageApi, /console\.log\(.*install/);
});

test("website visit counter persists in shared Redis storage", () => {
  assert.match(mainJs, /fetch\("\/api\/visits"/);
  assert.doesNotMatch(mainJs, /pipo-visits|sessionStorage/);
  assert.match(visitsApi, /const INITIAL_VISITS = 82/);
  assert.match(visitsApi, /pipo:website:visits/);
  assert.match(visitsApi, /\["SETNX", VISITS_KEY/);
  assert.match(visitsApi, /\["INCR", VISITS_KEY\]/);
});

test("website visit endpoint preserves baseline and increments shared count", async () => {
  const originalFetch = globalThis.fetch;
  const originalRedisUrl = process.env.UPSTASH_REDIS_REST_URL;
  const originalRedisToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  const store = new Map();

  process.env.UPSTASH_REDIS_REST_URL = "https://redis.test";
  process.env.UPSTASH_REDIS_REST_TOKEN = "test-token";
  globalThis.fetch = async (_url, options) => {
    const commands = JSON.parse(options.body);
    const results = commands.map(([command, key, value]) => {
      if (command === "SETNX") {
        if (store.has(key)) return 0;
        store.set(key, value);
        return 1;
      }
      if (command === "INCR") {
        const nextValue = Number(store.get(key)) + 1;
        store.set(key, String(nextValue));
        return nextValue;
      }
      throw new Error(`Unexpected Redis command: ${command}`);
    });
    return new Response(JSON.stringify(results.map((result) => ({ result }))), { status: 200 });
  };

  const invoke = async () => {
    const response = {
      statusCode: 0,
      body: null,
      headers: {},
      setHeader(name, value) { this.headers[name] = value; },
      status(statusCode) { this.statusCode = statusCode; return this; },
      json(body) { this.body = body; },
    };
    await visitsHandler({ method: "POST" }, response);
    return response;
  };

  try {
    assert.equal((await invoke()).body.visits, 82);
    assert.equal((await invoke()).body.visits, 83);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalRedisUrl === undefined) delete process.env.UPSTASH_REDIS_REST_URL;
    else process.env.UPSTASH_REDIS_REST_URL = originalRedisUrl;
    if (originalRedisToken === undefined) delete process.env.UPSTASH_REDIS_REST_TOKEN;
    else process.env.UPSTASH_REDIS_REST_TOKEN = originalRedisToken;
  }
});
