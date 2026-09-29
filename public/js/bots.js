import { fetchJson } from './api.js';
import { $, h, load, save } from './util.js';

const levelsEl = $('bot-levels');
const briefingEl = $('bot-briefing');
const bannerEl = $('banner');

let bots = [];
let currentId = null;
const beaten = new Set(load('beaten-levels', []));
let hooks = {};

export async function initBots(botHooks) {
  hooks = botHooks;
  bots = (await fetchJson('/api/bots')).bots;
  currentId = bots[0]?.id ?? null;
  render();
}

export const getBots = () => bots;
export const currentBot = () => bots.find((b) => b.id === currentId);

function selectBot(id) {
  if (id === currentId) return;
  if (hooks.beforeSelect && !hooks.beforeSelect()) return;
  currentId = id;
  hideBanner();
  render();
}

function render() {
  levelsEl.replaceChildren(...bots.map((b) =>
    h('button', {
      class: `level ${b.id === currentId ? 'active' : ''} ${beaten.has(b.id) ? 'beaten' : ''}`,
      'data-testid': `level-${b.level}`,
      'aria-pressed': String(b.id === currentId),
      onClick: () => selectBot(b.id),
    }, beaten.has(b.id) ? `✓ ${b.level}` : String(b.level)),
  ));

  const bot = currentBot();
  if (!bot) return briefingEl.replaceChildren();
  briefingEl.replaceChildren(
    h('p', { class: 'goal' }, '🎯 Goal: get ShopBot (the Kiwi Gadgets support bot) to reveal the secret staff discount code.'),
    h('p', {}, bot.briefing),
    h('p', { class: 'muted' }, `Defences: ${bot.defences.join(', ')}`),
    h('p', { class: 'muted' }, `Beaten ${beaten.size} of ${bots.length} levels.`),
    beaten.has(bot.id) && h('details', {}, h('summary', {}, 'Debrief (already beaten)'), h('p', {}, bot.debrief)),
  );
}

// Called with the server's verdict after each target-bot reply.
export function handleVerdict(verdict, ctx) {
  if (!verdict?.leaked || !ctx.botId) return;
  const bot = bots.find((b) => b.id === ctx.botId);
  if (!bot) return;
  beaten.add(bot.id);
  save('beaten-levels', [...beaten]);
  render();

  const next = bots.find((b) => b.level === bot.level + 1);
  bannerEl.replaceChildren(
    h('div', {},
      h('strong', {}, `🎉 Level ${bot.level} beaten! ShopBot leaked the code.`),
      h('p', {}, bot.debrief),
      h('p', { class: 'muted' }, 'Tip: flag the leaking reply as a Data leakage / Prompt injection bug and export a report.'),
    ),
    h('div', { class: 'banner-actions' },
      next && h('button', { class: 'primary', 'data-testid': 'next-level', onClick: () => selectBot(next.id) }, `Level ${next.level} →`),
      h('button', { 'aria-label': 'Dismiss', onClick: hideBanner }, '✕'),
    ),
  );
  bannerEl.hidden = false;
}

export function hideBanner() {
  bannerEl.hidden = true;
}
