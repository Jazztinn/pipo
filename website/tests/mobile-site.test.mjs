import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const indexHtml = await readFile(new URL("../index.html", import.meta.url), "utf8");
const mainJsx = await readFile(new URL("../src/main.jsx", import.meta.url), "utf8");
const mainJs = await readFile(new URL("../src/main.js", import.meta.url), "utf8");
const mobileCss = await readFile(new URL("../src/mobile/mobile.css", import.meta.url), "utf8");
const mobileSite = await readFile(new URL("../src/mobile/MobileSite.jsx", import.meta.url), "utf8");

test("mobile site mounts separately from desktop surface", () => {
  assert.match(indexHtml, /id="mobile-site-root"/);
  assert.match(indexHtml, /id="page-surface"/);
  assert.match(mainJsx, /createRoot\(document\.getElementById\("mobile-site-root"\)\)/);
  assert.match(mainJsx, /createRoot\(document\.getElementById\("macos-hero-root"\)\)/);
});

test("mobile CSS leaves desktop active above mobile breakpoint", () => {
  assert.match(mobileCss, /^#mobile-site-root\s*{\s*display:\s*none;/m);
  assert.match(mobileCss, /@media \(max-width: 1023px\)/);
  assert.match(mobileCss, /#page-surface,[\s\S]*display:\s*none !important;/);
  assert.doesNotMatch(mobileCss, /@media \(min-width:/);
});

test("desktop scroll engine stays inactive behind mobile surface", () => {
  assert.match(mainJs, /matchMedia\("\(min-width: 1024px\)"\)/);
  assert.match(mainJs, /desktopExperience\.matches\s*\n\s*\? initHorizontalScroll/);
  assert.match(mainJs, /addEventListener\("change", reloadAtExperienceBreakpoint\)/);
});

test("mobile site directs users to desktop live demo", () => {
  assert.match(mobileSite, /Live demo available on desktop/);
  assert.match(mobileSite, /live demo/);
  assert.match(mobileSite, /Share desktop link/);
});

test("mobile site stays a single landing surface with file-safe assets", () => {
  assert.equal((mobileSite.match(/<section/g) ?? []).length, 1);
  assert.doesNotMatch(mobileSite, /Pipo for macOS/);
  assert.doesNotMatch(mobileSite, /mobile-notice-icon/);
  assert.doesNotMatch(mobileSite, /src="\/pipo-logo\.png"/);
  assert.match(mobileSite, /src="\.\/pipo-logo\.png"/);
});
