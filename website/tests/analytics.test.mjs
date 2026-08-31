import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const mainJs = await readFile(new URL("../src/main.js", import.meta.url), "utf8");
const privacyHtml = await readFile(new URL("../privacy.html", import.meta.url), "utf8");

test("website injects Vercel Web Analytics", () => {
  assert.match(mainJs, /import \{ inject \} from "@vercel\/analytics"/);
  assert.match(mainJs, /inject\(\);/);
});

test("privacy policy discloses analytics and feedback delivery", () => {
  assert.match(privacyHtml, /Vercel Web Analytics/);
  assert.match(privacyHtml, /Resend/);
  assert.doesNotMatch(privacyHtml, /no analytics integration/);
});
