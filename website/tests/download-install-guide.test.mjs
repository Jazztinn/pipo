import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("desktop download links fetch the DMG and expose installation guide", async () => {
  const html = await readFile(new URL("index.html", root), "utf8");
  const links = [...html.matchAll(/<a[^>]+href="\/api\/download"[^>]*>/g)];

  assert.equal(links.length, 3);
  links.forEach(([link]) => {
    assert.match(link, /download="Pipo-0\.5\.3-universal\.dmg"/);
    assert.match(link, /data-download-guide/);
  });

  assert.match(html, /<dialog[^>]+data-install-guide/);
  assert.match(html, /aria-labelledby="install-guide-title"/);
  assert.doesNotMatch(html, /Download started/);
  assert.match(html, /cannot be verified or may be potentially harmful/);
  assert.match(html, /Pipo cannot receive, transmit, or store your password/);
  assert.match(html, /Pipo will never ask for your Mac password inside the app or this website/);
});

test("installation guide opens only for desktop download links", async () => {
  const script = await readFile(new URL("src/main.js", root), "utf8");

  assert.match(script, /matchMedia\("\(min-width: 1024px\)"\)/);
  assert.match(script, /installGuide\.showModal\(\)/);
  assert.match(script, /installGuide\?\.close\(\)/);
  assert.match(script, /classList\.add\("is-open"\)/);
  assert.match(script, /classList\.add\("is-closing"\)/);
  assert.match(script, /prefers-reduced-motion: reduce/);
  assert.match(script, /link\?\.matches\("\[data-download-guide\]"\)/);
  assert.match(script, /event\.key !== "Escape"/);
  assert.match(script, /downloadGuideTrigger\?\.focus\(\)/);
});
