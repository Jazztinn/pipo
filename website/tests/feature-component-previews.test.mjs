import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const websiteRoot = resolve(import.meta.dirname, "..");
const repoRoot = resolve(websiteRoot, "..");
const previewNames = [];
const graphicNames = ["next-up-graphic", "today-graphic", "quick-actions-graphic", "readonly-graphic"];
const supportedPreviewNames = ["nextUp", "today", "quickActions", "resources"];

test("feature cards render Pipo-style graphics without embedded previews", async () => {
  const page = await readFile(resolve(websiteRoot, "index.html"), "utf8");
  const sources = [...page.matchAll(/<div class="feature-showcase[^"]*">\s*<iframe[^>]+src="([^"]+)"/g)]
    .map((match) => match[1].replaceAll("&amp;", "&"));

  assert.equal(sources.length, previewNames.length);
  const components = sources.map((source) => {
    const url = new URL(source, "https://pipo.test");
    assert.equal(url.pathname, "/pipo-menu/index.html");
    assert.equal(url.searchParams.get("embedded"), "1");
    assert.equal(url.searchParams.get("mode"), "demo");
    return url.searchParams.get("component");
  });
  assert.deepEqual(components.sort(), previewNames.toSorted());

  for (const graphicName of graphicNames) {
    assert.match(page, new RegExp(`class="[^"]*\\b${graphicName}\\b`));
  }
});

test("canonical MenuWeb supports every feature preview", async () => {
  const menuRoot = resolve(repoRoot, "app/Sources/PipoUI/Resources/MenuWeb");
  const [html, runtime] = await Promise.all([
    readFile(resolve(menuRoot, "index.html"), "utf8"),
    readFile(resolve(menuRoot, "menu.js"), "utf8"),
  ]);
  const supportedSet = runtime.match(/const componentNames = new Set\(\[([^\]]+)]\)/);

  assert.ok(supportedSet, "MenuWeb must declare supported component previews");
  const supportedNames = [...supportedSet[1].matchAll(/['"]([^'"]+)['"]/g)].map((match) => match[1]);
  assert.deepEqual(supportedNames.sort(), supportedPreviewNames.toSorted());
  assert.match(runtime, /params\.get\(['"]component['"]\)/);
  assert.match(runtime, /dataset\.componentPreviewReady = ['"]true['"]/);
  assert.match(html, /id="inspector-quick-actions"/);

  for (const name of supportedPreviewNames) {
    assert.match(html, new RegExp(`data-component-preview="${name}"`));
  }
});
