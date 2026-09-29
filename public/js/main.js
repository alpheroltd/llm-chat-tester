import { fetchJson } from './api.js';
import { initBots, currentBot, getBots, handleVerdict, hideBanner } from './bots.js';
import { initChat, clearChat, hasMessages, insertPrompt, getMessages } from './chat.js';
import { exportReport } from './flags.js';
import { initJudge } from './judge.js';
import { initMissions, currentMission } from './missions.js';
import { getOptions, setOptions } from './settings.js';
import { initTestCases, openEditor } from './testcases.js';
import { $ } from './util.js';

const modelSelect = $('model-select');
const systemPromptEl = $('system-prompt');
let mode = 'free';

// ---- Models / status ----

function setStatus(state, text) {
  $('status-dot').className = `dot ${state}`;
  $('status-text').textContent = text;
}

async function loadModels() {
  setStatus('', 'Checking…');
  try {
    const { models } = await fetchJson('/api/models');
    const previous = modelSelect.value;
    modelSelect.replaceChildren(...models.map((name) => new Option(name, name)));
    if (models.includes(previous)) modelSelect.value = previous;
    if (models.length === 0) setStatus('error', 'No models. Run: ollama pull llama3.2:3b');
    else setStatus('ok', 'Ollama connected');
  } catch (err) {
    modelSelect.replaceChildren();
    setStatus('error', 'Ollama not reachable');
    console.error(err);
  }
}

// ---- Tabs ----

function switchTab(tab) {
  for (const btn of document.querySelectorAll('.tab')) {
    const active = btn.dataset.tab === tab;
    btn.classList.toggle('active', active);
    btn.setAttribute('aria-selected', String(active));
  }
  for (const view of document.querySelectorAll('.view')) view.hidden = view.id !== `view-${tab}`;
}

// ---- Modes ----

function confirmClear() {
  return !hasMessages() || confirm('This will clear the current chat. Continue?');
}

function setMode(next, { skipConfirm = false } = {}) {
  if (next !== mode) {
    if (!skipConfirm && !confirmClear()) {
      document.querySelector(`input[name="mode"][value="${mode}"]`).checked = true;
      return;
    }
    clearChat();
    hideBanner();
    mode = next;
  }
  document.querySelector(`input[name="mode"][value="${mode}"]`).checked = true;
  $('bot-panel').hidden = mode !== 'bot';
  $('mission-panel').hidden = mode !== 'mission';
  $('system-section').hidden = mode === 'bot';
  switchTab('chat');
}

function getContext() {
  const bot = mode === 'bot' ? currentBot() : null;
  const mission = mode === 'mission' ? currentMission() : null;
  return {
    model: modelSelect.value,
    botId: bot?.id,
    systemPrompt: bot ? '' : systemPromptEl.value.trim(),
    options: getOptions(),
    modeLabel: bot ? `Target bot: ${bot.name}` : mission ? `Mission: ${mission.title}` : 'Free chat',
  };
}

// ---- Wiring ----

for (const radio of document.querySelectorAll('input[name="mode"]')) {
  radio.addEventListener('change', () => setMode(radio.value));
}
for (const btn of document.querySelectorAll('.tab')) {
  btn.addEventListener('click', () => switchTab(btn.dataset.tab));
}
$('refresh-btn').addEventListener('click', loadModels);
$('clear-btn').addEventListener('click', () => {
  clearChat();
  hideBanner();
});
$('export-btn').addEventListener('click', () => {
  if (!hasMessages()) return alert('Nothing to export yet. Chat first, and flag replies with ⚑.');
  exportReport(getMessages());
});

initChat({
  getContext,
  onVerdict: handleVerdict,
  onBusyChange: (busy) => (modelSelect.disabled = busy),
  onSaveAsTestCase: ({ prompt, systemPrompt, botId }) => {
    switchTab('tests');
    openEditor({ prompt, systemPrompt, botId: botId ?? '' });
  },
});

initMissions({
  onInsertPrompt: (text) => {
    switchTab('chat');
    insertPrompt(text);
  },
  onApplySetup: ({ systemPrompt, settings, goTo }) => {
    if (systemPrompt) systemPromptEl.value = systemPrompt;
    if (settings) setOptions(settings);
    if (goTo === 'bot') setMode('bot');
    if (goTo === 'tests' || goTo === 'judge') switchTab(goTo);
  },
});

initBots({
  beforeSelect: () => {
    if (!confirmClear()) return false;
    clearChat();
    return true;
  },
}).catch((err) => ($('bot-briefing').textContent = `Could not load bots: ${err.message}`));

initTestCases({ getModel: () => modelSelect.value, getBots });
initJudge({ getModel: () => modelSelect.value, getSidebarSystemPrompt: () => getContext().systemPrompt });

setMode('free', { skipConfirm: true });
loadModels();
