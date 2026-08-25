import test from "node:test";
import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
test("website includes canonical Pipo MenuWeb bundle", async () => {
  for (const file of ["index.html", "menu.css", "menu.js", "demo-fixture.json", "pipoclick.mp3", "css/fontawesome.min.css"]) {
    await assert.doesNotReject(access(resolve(root, "public/pipo-menu", file)));
  }
  const html = await readFile(resolve(root, "public/pipo-menu/index.html"), "utf8");
  assert.match(html, /menu\.js/);
  assert.doesNotMatch(html, /https:\/\//);
  const hash = createHash("sha256");
  for (const file of ["index.html", "menu.css", "menu.js", "demo-fixture.json", "pipoclick.mp3", "css/fontawesome.min.css", "webfonts/fa-regular-400.woff2", "webfonts/fa-solid-900.woff2"]) hash.update(await readFile(resolve(root, "public/pipo-menu", file)));
  assert.equal((await readFile(resolve(root, "public/pipo-menu/.canonical-sha256"), "utf8")).trim(), hash.digest("hex"));
  const runtime = await readFile(resolve(root, "public/pipo-menu/menu.js"), "utf8");
  for (const action of ["ui.ready", "refresh", "selectTab", "markSeen", "snooze", "openDestination", "copyDetails", "addToCalendar", "setInspectorVisible", "signOut"]) assert.match(runtime, new RegExp(action.replace(".", "\\.")));
  assert.match(runtime, /textContent/);
  assert.match(runtime, /mode === 'demo'/);
  const fixture = JSON.parse(await readFile(resolve(root, "public/pipo-menu/demo-fixture.json"), "utf8"));
  assert.equal(fixture.studentName, "Samwise");
  assert.ok(fixture.courses.length >= 6);
  for (const section of ["nextUp", "schedule", "dueSoon", "newAssignments", "notifications", "messages", "gradeFeedback", "announcements", "resources"]) {
    assert.ok(fixture[section].length, `${section} needs demo content`);
  }
  assert.ok(fixture.courses.every(course => course.id && course.name && course.shortName));
  assert.ok(fixture.localState.pinnedCourseIDs.length && fixture.localState.hiddenCourseIDs.length);
  assert.doesNotMatch(runtime, /innerHTML/);
  assert.match(runtime, /addEventListener\('pipo-state'/);
  assert.match(runtime, /addEventListener\('pipo-response'/);
  assert.match(runtime, /nativeBridge\.request\(action, outbound\)/);
  assert.match(runtime, /requestID: generatedID/);
  assert.match(runtime, /renderState\(state\)/);
  assert.match(runtime, /switchTab\(state\.selectedTab \|\| 'today', false\)/);
  assert.match(runtime, /refreshMinutes/);
  assert.match(runtime, /requestCalendarAccess/);
  assert.doesNotMatch(runtime, /\$\{action\} complete/);
  assert.match(runtime, /source === 'inspector'/);
  assert.match(runtime, /actionButton\.closest\('#inspector-panel'\)/);
  for (const action of ["loadCourse", "updateSettings", "updateChannel"]) assert.match(runtime, new RegExp(action));
  assert.match(runtime, /shortName/);
  assert.match(runtime, /short_name/);
  assert.match(runtime, /course_name/);
  assert.match(runtime, /published_grade/);
  assert.match(runtime, /timestamp/);
  assert.doesNotMatch(runtime, /Untitled item|Details unavailable|Course details unavailable/);
  assert.match(html, /id="main-navigation"/);
  assert.match(html, /id="sync-button"[^>]+data-action="refresh"/);
  assert.match(runtime, /mac-card rounded-xl p-2\.5 space-y-1\.5/);
  assert.doesNotMatch(runtime, /Published grade:.*assignments.*grade entries/s);
});
