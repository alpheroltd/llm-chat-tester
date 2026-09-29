import { MISSIONS } from '../data/missions.js';
import { $, h, load, save } from './util.js';

const listEl = $('mission-list');
const detailEl = $('mission-detail');
const progressEl = $('mission-progress');

const done = new Set(load('missions-done', []));
let currentId = MISSIONS[0].id;
let hooks = {};

export function initMissions(missionHooks) {
  hooks = missionHooks;
  render();
}

export const currentMission = () => MISSIONS.find((m) => m.id === currentId);

function describeSetup({ systemPrompt, settings, goTo }) {
  const parts = [];
  if (systemPrompt) parts.push('fills in the system prompt');
  if (settings) parts.push(`sets ${Object.entries(settings).map(([k, v]) => `${k} ${v}`).join(', ')}`);
  if (goTo === 'bot') parts.push('switches to Target bots');
  if (goTo === 'tests') parts.push('opens the Test cases tab');
  if (goTo === 'judge') parts.push('opens the LLM-as-a-judge tab');
  return parts.join(', ');
}

function render() {
  progressEl.textContent = `${done.size} of ${MISSIONS.length} complete`;
  listEl.replaceChildren(...MISSIONS.map((m) =>
    h('li', {},
      h('button', {
        class: `mission ${m.id === currentId ? 'active' : ''}`,
        'data-testid': `mission-${m.id}`,
        onClick: () => { currentId = m.id; render(); },
      }, h('span', { class: 'check' }, done.has(m.id) ? '✓' : '○'), ` ${m.title}`),
    ),
  ));

  const m = currentMission();
  const isDone = done.has(m.id);
  detailEl.replaceChildren(
    h('h3', {}, m.title),
    h('span', { class: 'chip' }, m.category),
    h('p', {}, h('strong', {}, 'Goal: '), m.goal),
    m.setup && h('p', {},
      h('button', { 'data-testid': 'mission-apply-setup', onClick: () => hooks.onApplySetup?.(m.setup) }, 'Apply setup'),
      h('span', { class: 'muted' }, ` ${describeSetup(m.setup)}`)),
    m.prompts.length > 0 && h('div', {},
      h('p', { class: 'label' }, 'Try these prompts (click to use):'),
      h('ul', { class: 'prompt-list' }, m.prompts.map((p) =>
        h('li', {}, h('button', { class: 'prompt-chip', onClick: () => hooks.onInsertPrompt?.(p) }, p))))),
    h('details', {}, h('summary', {}, '💡 Hints'), h('ol', {}, m.hints.map((t) => h('li', {}, t)))),
    h('p', {}, h('strong', {}, '🐞 What a bug looks like: '), m.bug),
    h('p', { class: 'muted' }, h('strong', {}, '🌍 In the real world: '), m.realWorld),
    h('button', {
      class: isDone ? '' : 'primary',
      'data-testid': 'mission-complete',
      onClick: () => {
        isDone ? done.delete(m.id) : done.add(m.id);
        save('missions-done', [...done]);
        render();
      },
    }, isDone ? '✓ Completed (undo)' : 'Mark complete'),
  );
}
