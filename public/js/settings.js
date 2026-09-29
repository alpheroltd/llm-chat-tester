import { $ } from './util.js';

const tempEl = $('temperature');
const tempOut = $('temp-value');
const seedEl = $('seed');
const maxEl = $('max-tokens');

tempEl.addEventListener('input', () => (tempOut.textContent = tempEl.value));

// Ollama `options` for the current settings. Blank seed/max tokens are left out (random / no limit).
export function getOptions() {
  const options = { temperature: Number(tempEl.value) };
  if (seedEl.value !== '') options.seed = parseInt(seedEl.value, 10);
  if (maxEl.value !== '') options.num_predict = parseInt(maxEl.value, 10);
  return options;
}

export function setOptions({ temperature, seed, num_predict } = {}) {
  if (temperature != null) {
    tempEl.value = temperature;
    tempOut.textContent = tempEl.value;
  }
  if (seed !== undefined) seedEl.value = seed ?? '';
  if (num_predict !== undefined) maxEl.value = num_predict ?? '';
}

export function describeOptions(options) {
  return [
    `temp ${options.temperature}`,
    options.seed != null ? `seed ${options.seed}` : 'seed random',
    options.num_predict ? `max ${options.num_predict} tokens` : null,
  ].filter(Boolean).join(' · ');
}
