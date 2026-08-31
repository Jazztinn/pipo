export const BOAT_WAVE_WIDTH = 320;
export const BOAT_WAVE_HEIGHT = 48;

const TAU = Math.PI * 2;

const waveParts = [
  { amplitude: 4.15, wavelength: 118, speed: 0.34, phase: 0.2 },
  { amplitude: -1.45, wavelength: 73, speed: 0.19, phase: 1.15 },
  { amplitude: 0.55, wavelength: 187, speed: 0.11, phase: 2.4 },
];

export function sampleBoatWave(x, time = 0) {
  let y = 28;
  let slope = 0;

  waveParts.forEach(({ amplitude, wavelength, speed, phase }) => {
    const waveNumber = TAU / wavelength;
    const angle = waveNumber * x - speed * time + phase;
    y += amplitude * Math.sin(angle);
    slope += amplitude * waveNumber * Math.cos(angle);
  });

  return { y, slope };
}

export function createBoatWavePath(time = 0, segments = 112) {
  const points = [];

  for (let index = 0; index <= segments; index += 1) {
    const x = (index / segments) * BOAT_WAVE_WIDTH;
    const { y } = sampleBoatWave(x, time);
    points.push(`${index === 0 ? "M" : "L"}${x.toFixed(2)} ${y.toFixed(2)}`);
  }

  return points.join(" ");
}
