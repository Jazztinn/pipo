import assert from "node:assert/strict";
import test from "node:test";

import {
  BOAT_WAVE_WIDTH,
  createBoatWavePath,
  sampleBoatWave,
} from "../src/boat-wave.js";

test("boat wave slope matches nearby surface samples", () => {
  const x = 137;
  const time = 4.2;
  const distance = 0.01;
  const before = sampleBoatWave(x - distance, time);
  const current = sampleBoatWave(x, time);
  const after = sampleBoatWave(x + distance, time);
  const sampledSlope = (after.y - before.y) / (distance * 2);

  assert.ok(Math.abs(current.slope - sampledSlope) < 0.00001);
});

test("boat wave stays restrained across full navigation span", () => {
  for (let time = 0; time <= 20; time += 1) {
    for (let x = 0; x <= BOAT_WAVE_WIDTH; x += 4) {
      const { y, slope } = sampleBoatWave(x, time);
      assert.ok(y >= 21 && y <= 35);
      assert.ok(Math.abs(slope) < 0.37);
    }
  }
});

test("visible path is built from shared boat wave samples", () => {
  const time = 3;
  const path = createBoatWavePath(time, 4);
  const end = sampleBoatWave(BOAT_WAVE_WIDTH, time);

  assert.match(path, /^M0\.00 /);
  assert.ok(path.endsWith(`L${BOAT_WAVE_WIDTH.toFixed(2)} ${end.y.toFixed(2)}`));
});
