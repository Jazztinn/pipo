import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import vm from "node:vm";

async function loadHelpers() {
  const source = await readFile(resolve(import.meta.dirname, "../../app/Sources/PipoUI/Resources/MenuWeb/menu-helpers.js"), "utf8");
  const context = { window: {} };
  vm.runInNewContext(source, context);
  return context.window.pipoMenuHelpers;
}

test("context actions dispatch typed course and imported schedule operations", async () => {
  const helper = await loadHelpers();
  const actions = (item, type, pinned) => Array.from(helper.contextActions(item, type, pinned), entry => entry.action);
  assert.deepEqual(actions({ id: "12" }, "course", false), ["openDestination", "copyDetails", "pinCourse", "hideCourse"]);
  assert.deepEqual(actions({ id: "12" }, "course", true), ["openDestination", "copyDetails", "unpinCourse", "hideCourse"]);
  for (const kind of ["imported_class", "imported_subject"]) {
    assert.deepEqual(actions({ kind }, "activity"), ["editSchedule", "copyDetails"]);
  }
  assert.ok(actions({ kind: "calendar", section: "schedule", destinationAvailable: true }, "activity").includes("openDestination"));
});

test("greeting uses stable local-hour periods", async () => {
  const helper = await loadHelpers();
  assert.equal(helper.greetingPeriod(4), "lateNight");
  assert.equal(helper.greetingPeriod(5), "morning");
  assert.equal(helper.greetingPeriod(12), "afternoon");
  assert.equal(helper.greetingPeriod(17), "evening");
  assert.equal(helper.greetingPeriod(22), "lateNight");
});

test("each period has deterministic greeting variants", async () => {
  const helper = await loadHelpers();
  for (const hour of [6, 13, 18, 23]) {
    const choices = Array.from(helper.greetingsForHour(hour));
    assert.ok(new Set(choices).size >= 3);
    assert.equal(helper.chooseGreeting(hour, 0), choices[0]);
    assert.equal(helper.chooseGreeting(hour, 0.999), choices.at(-1));
    assert.equal(helper.chooseGreeting(hour, 0.51), helper.chooseGreeting(hour, 0.51));
  }
});

test("instructor prefers field, then strict course-title suffix, then fallback", async () => {
  const helper = await loadHelpers();
  assert.equal(helper.instructorFor({ instructor: "Professor Minerva McGonagall", courseName: "Wrong (Mr. Wrong)" }), "Professor Minerva McGonagall");
  assert.equal(helper.instructorFor({ courseName: "Operating Systems (Mr. Feranil, Edison)" }), "Mr. Feranil, Edison");
  assert.equal(helper.instructorFor({ course_name: "Potions (Professor Severus Snape)" }), "Professor Severus Snape");
  assert.equal(helper.instructorFor({ courseName: "Algorithms (Advanced)" }), "Instructor unavailable");
  assert.equal(helper.instructorFor({ title: "Assignment (Professor Fake)" }), "Instructor unavailable");
});

test("missing LMS values and section phases have safe presentations", async () => {
  const helper = await loadHelpers();
  for (const missing of [null, undefined, false, "", "null", "undefined", "Not supplied"]) {
    assert.equal(helper.safeDisplay(missing, "Value unavailable"), "Value unavailable");
  }
  assert.deepEqual({ ...helper.sectionPresentation("loading", "Messages") }, { kind: "loading", text: "Loading messages…", retry: false });
  assert.deepEqual({ ...helper.sectionPresentation("failed", "Messages") }, { kind: "error", text: "Messages could not load.", retry: true });
  assert.deepEqual({ ...helper.sectionPresentation("ready", "Messages") }, { kind: "empty", text: "No messages", retry: false });
  assert.deepEqual({ ...helper.sectionPresentation("failed", "Messages", 1) }, { kind: "content", text: "", retry: false });
  assert.deepEqual({ ...helper.sectionPresentation("partial", "Messages") }, { kind: "warning", text: "Messages are incomplete. Retry to load remaining items.", retry: true });
  assert.equal(helper.sectionPresentation("unsupported", "Messages").retry, false);
  assert.equal(helper.sectionPresentation("authentication_required", "Messages").text, "Sign in again to load messages.");
});

test("grades preserve LMS formatting and fall back to raw points", async () => {
  const helper = await loadHelpers();
  assert.equal(helper.gradeDisplay({ published_grade: "18 / 20" }), "18 / 20");
  assert.equal(helper.gradeDisplay({ gradeformatted: "—", percentageformatted: "92%" }), "92%");
  assert.equal(helper.gradeDisplay({ gradeformatted: "1.50" }), "1.50");
  assert.equal(helper.gradeDisplay({ graderaw: 18, grademax: 20 }), "18 / 20");
  assert.equal(helper.gradeDisplay({ gradeformatted: "-" }), null);
});

test("runtime chooses one document greeting outside render loop", async () => {
  const runtime = await readFile(resolve(import.meta.dirname, "../../app/Sources/PipoUI/Resources/MenuWeb/menu.js"), "utf8");
  const html = await readFile(resolve(import.meta.dirname, "../../app/Sources/PipoUI/Resources/MenuWeb/index.html"), "utf8");
  assert.equal((runtime.match(/chooseGreeting\(/g) || []).length, 1);
  assert.match(runtime, /const documentGreeting =/);
  assert.match(html, /id="today-greeting"/);
  assert.match(runtime, /`\$\{documentGreeting\}\$\{state\.studentName/);
  assert.match(runtime, /instructorFor\(item\).*Instructor unavailable/);
});

test("runtime exposes complete async states and stale-response guards", async () => {
  const runtime = await readFile(resolve(import.meta.dirname, "../../app/Sources/PipoUI/Resources/MenuWeb/menu.js"), "utf8");
  assert.match(runtime, /setActionPending\(trigger, true\)/);
  assert.match(runtime, /setActionPending\(pending\?\.trigger, false\)/);
  assert.match(runtime, /Pipo did not respond\. Try again\./);
  assert.match(runtime, /Course details could not load\./);
  assert.match(runtime, /dataset\.action = 'refreshSection'/);
  assert.match(runtime, /dataset\.action = 'loadCourse'/);
  assert.match(runtime, /tokenMatches/);
  assert.match(runtime, /responseRevision >= revision/);
  assert.match(runtime, /requests\.has\(response\.requestID\)/);
  assert.match(runtime, /addEventListener\('unhandledrejection'/);
  assert.match(runtime, /event\.preventDefault\(\)/);
  assert.doesNotMatch(runtime, /Course not supplied|No date supplied/);
});

test("refresh slider uses one explicit stepped control and syncs visible value", async () => {
  const runtime = await readFile(resolve(import.meta.dirname, "../../app/Sources/PipoUI/Resources/MenuWeb/menu.js"), "utf8");
  const html = await readFile(resolve(import.meta.dirname, "../../app/Sources/PipoUI/Resources/MenuWeb/index.html"), "utf8");
  assert.match(html, /id="refresh-slider"[^>]+min="5" max="60" step="5" value="15"/);
  assert.match(html, /id="refresh-label"/);
  assert.match(html, /id="refresh-value"[^>]+for="refresh-slider"/);
  assert.match(runtime, /function syncRefreshControl\(value\)/);
  assert.match(runtime, /syncRefreshControl\(state\.settings\.refreshMinutes\)/);
  assert.match(runtime, /aria-valuetext/);
});

test("update presentation stays global, dismissible, and accessible", async () => {
  const runtime = await readFile(resolve(import.meta.dirname, "../../app/Sources/PipoUI/Resources/MenuWeb/menu.js"), "utf8");
  const html = await readFile(resolve(import.meta.dirname, "../../app/Sources/PipoUI/Resources/MenuWeb/index.html"), "utf8");
  assert.match(html, /id="update-notice"[^>]+role="status"[^>]+aria-live="polite"/);
  assert.match(html, /data-action="viewUpdate"/);
  assert.match(html, /data-action="dismissUpdate"/);
  assert.match(html, /role="dialog" aria-modal="true" aria-labelledby="whats-new-title"/);
  assert.match(html, /data-action="dismissWhatsNew"/);
  assert.match(runtime, /notice\.severity === 'critical'/);
  assert.match(runtime, /dismiss\.hidden = notice\?\.severity === 'critical'/);
  assert.match(runtime, /addEventListener\('pipo-reset-session'/);
  assert.match(runtime, /requests\.clear\(\)/);
});
