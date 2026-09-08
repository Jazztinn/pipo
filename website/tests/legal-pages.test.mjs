import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const websiteRoot = resolve(import.meta.dirname, "..");
const effectiveDate = "August 31, 2026";

for (const [file, title, canonical, counterpart] of [
  ["terms.html", "Terms of Use — Pipo", "https://pipo.jazztinn.me/terms.html", "./privacy.html"],
  ["privacy.html", "Privacy Policy — Pipo", "https://pipo.jazztinn.me/privacy.html", "./terms.html"],
]) {
  test(`${file} keeps stable production metadata`, async () => {
    const html = await readFile(resolve(websiteRoot, file), "utf8");
    assert.match(html, new RegExp(`<title>${title}</title>`));
    assert.match(html, new RegExp(`<link rel="canonical" href="${canonical}"`));
    assert.match(html, new RegExp(`Effective ${effectiveDate}`));
    assert.match(html, new RegExp(`href="${counterpart.replace(".", "\\.")}"`));
    assert.match(html, /href="\.\/index\.html"/);
    assert.match(html, /href="\/api\/download" download="Pipo-0\.5\.3-universal\.dmg" data-pipo-download/);
  });
}

test("app packaging copies canonical license and notices", async () => {
  const script = await readFile(resolve(websiteRoot, "../scripts/build-local-beta.sh"), "utf8");
  assert.match(script, /Contents\/Resources\/Legal/);
  assert.match(script, /\$ROOT\/LICENSE/);
  assert.match(script, /\$ROOT\/THIRD_PARTY_NOTICES\.md/);
  assert.match(script, /test -s "\$APP\/Contents\/Resources\/Legal\/LICENSE\.txt"/);
  assert.match(script, /test -s "\$APP\/Contents\/Resources\/Legal\/THIRD_PARTY_NOTICES\.md"/);
});

test("bundled legal notices match their canonical project documents", async () => {
  const projectRoot = resolve(websiteRoot, "..");
  const [license, bundledLicense, notices, bundledNotices] = await Promise.all([
    readFile(resolve(projectRoot, "LICENSE")),
    readFile(resolve(projectRoot, "app/Sources/PipoUI/Resources/Legal/LICENSE.txt")),
    readFile(resolve(projectRoot, "THIRD_PARTY_NOTICES.md")),
    readFile(resolve(projectRoot, "app/Sources/PipoUI/Resources/Legal/THIRD_PARTY_NOTICES.md")),
  ]);
  assert.deepEqual(bundledLicense, license);
  assert.deepEqual(bundledNotices, notices);
});
