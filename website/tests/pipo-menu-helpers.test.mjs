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

test("runtime chooses one document greeting outside render loop", async () => {
  const runtime = await readFile(resolve(import.meta.dirname, "../../app/Sources/PipoUI/Resources/MenuWeb/menu.js"), "utf8");
  const html = await readFile(resolve(import.meta.dirname, "../../app/Sources/PipoUI/Resources/MenuWeb/index.html"), "utf8");
  assert.equal((runtime.match(/chooseGreeting\(/g) || []).length, 1);
  assert.match(runtime, /const documentGreeting =/);
  assert.match(html, /id="today-greeting"/);
  assert.match(runtime, /`\$\{documentGreeting\}\$\{state\.studentName/);
  assert.match(runtime, /instructorFor\(item\).*Instructor unavailable/);
});
