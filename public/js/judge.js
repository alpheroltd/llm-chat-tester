import { EXERCISES, RUBRIC_PRESETS } from '../data/judge-exercises.js';
import { buildMessages, fetchJson, streamChat } from './api.js';
import { getOptions } from './settings.js';
import { $, h, load, save } from './util.js';

const view = $('view-judge');
const progress = load('judge-exercises', {}); // id → { mine, judge, expected }
const history = [];
let hooks = {};
let controller = null;
let activeExercise = null;
let prediction = { verdict: null, score: '' };

// Form controls, created once and reused so typed text survives re-renders.
const modelSelect = h('select', { 'data-testid': 'judge-model', 'aria-label': 'Judge model' },
  h('option', { value: 'haiku' }, 'Claude Haiku (fast, cheap)'),
  h('option', { value: 'sonnet' }, 'Claude Sonnet'),
  h('option', { value: 'opus' }, 'Claude Opus (strongest)'));
const presetSelect = h('select', { 'data-testid': 'judge-preset', 'aria-label': 'Rubric preset', onChange: applyPreset },
  h('option', { value: '' }, 'Custom rubric'),
  RUBRIC_PRESETS.map((p) => h('option', { value: p.id }, p.name)));
const rubricEl = h('textarea', {
  rows: 4, 'data-testid': 'judge-rubric', placeholder: 'One criterion per line, e.g.\nStates the returns window is 30 days.\nFriendly, professional tone.',
  onInput: () => (presetSelect.value = ''),
});
const questionEl = h('textarea', { rows: 2, 'data-testid': 'judge-question', placeholder: 'What the user asked the chatbot' });
const systemEl = h('textarea', { rows: 3, 'data-testid': 'judge-system', placeholder: "The chatbot's instructions, if the rubric depends on them" });
const replyEl = h('textarea', { rows: 5, 'data-testid': 'judge-reply', placeholder: 'Paste a reply, or generate one with the local model' });
const generateBtn = h('button', { type: 'button', 'data-testid': 'judge-generate', onClick: generateReply }, '✨ Generate reply with local model');
const judgeBtn = h('button', { class: 'primary', 'data-testid': 'judge-run', onClick: () => judge(1) }, '⚖ Judge');
const judge3Btn = h('button', { 'data-testid': 'judge-run-3', onClick: () => judge(3) }, '⚖ Judge ×3');
const stopBtn = h('button', { 'data-testid': 'judge-stop', hidden: true, onClick: () => controller?.abort() }, 'Stop');
const statusDot = h('span', { class: 'dot' });
const statusText = h('span', {}, 'Checking Claude…');
const errorEl = h('p', { class: 'error-text', 'data-testid': 'judge-error' });
const exercisesEl = h('div');
const resultsEl = h('div', { class: 'judge-results', 'data-testid': 'judge-results' });
const historyEl = h('div');

export function initJudge(judgeHooks) {
  hooks = judgeHooks;
  view.replaceChildren(
    h('section', { class: 'card' },
      h('h2', { class: 'view-title' }, 'LLM-as-a-judge'),
      h('p', {}, "An LLM judge grades a chatbot's reply against a rubric you write. Teams use this to test chatbots at scale, because no human can read every reply. Judges make mistakes too, so part of your job is learning when to trust them."),
      h('div', { class: 'row' },
        h('label', { class: 'inline' }, 'Judge ', modelSelect),
        h('span', { class: 'status', 'data-testid': 'judge-status' }, statusDot, statusText)),
      h('p', { class: 'hint' }, 'The judge runs on Claude via Claude Code, so the text you judge is sent to Anthropic. The chatbot being tested still runs locally.')),
    exercisesEl,
    h('section', { class: 'card' },
      h('div', { class: 'row spread' }, h('h3', {}, '1. Rubric'), presetSelect),
      rubricEl,
      h('p', { class: 'hint' }, 'Write one criterion per line. Every criterion must be met to pass. Vague rubrics give vague verdicts.')),
    h('section', { class: 'card' },
      h('h3', {}, '2. What to judge'),
      h('label', { class: 'block' }, "Bot's system prompt (optional)", systemEl),
      h('p', { class: 'hint' }, "The chatbot's instructions. Used when generating a reply, and shown to the judge. If left empty, the sidebar's system prompt is used."),
      h('label', { class: 'block' }, 'Question', questionEl),
      h('label', { class: 'block' }, 'Reply', replyEl),
      h('div', { class: 'row' }, generateBtn,
        h('span', { class: 'hint' }, 'Uses the model and settings on the left, with the question and system prompt above.'))),
    h('div', { class: 'row' }, judgeBtn, judge3Btn, stopBtn),
    errorEl,
    resultsEl,
    historyEl,
  );
  renderExercises();
  renderHistory();
  checkStatus();
}

async function checkStatus() {
  try {
    const s = await fetchJson('/api/judge/status');
    statusDot.className = `dot ${s.available ? 'ok' : 'error'}`;
    statusText.textContent = s.available ? `Claude Code ${s.version.split(' ')[0]} ready` : s.error;
  } catch (err) {
    statusDot.className = 'dot error';
    // A 404 here means the page is newer than the running server (it was started before the judge existed).
    statusText.textContent = err.message === 'Not found'
      ? 'Judge not available: restart the server (Ctrl+C, then npm start)'
      : err.message;
  }
}

function applyPreset() {
  const preset = RUBRIC_PRESETS.find((p) => p.id === presetSelect.value);
  if (preset) rubricEl.value = preset.rubric;
}

function setRunning(running) {
  for (const btn of [judgeBtn, judge3Btn, generateBtn]) btn.disabled = running;
  stopBtn.hidden = !running;
}

// ---- Generate a reply with the local chatbot ----

async function generateReply() {
  errorEl.textContent = '';
  const model = hooks.getModel();
  if (!model) return (errorEl.textContent = 'Select a local model at the top first.');
  if (!questionEl.value.trim()) return (errorEl.textContent = 'Type a question first.');
  // Fall back to the sidebar's system prompt, and copy it in so the judge sees the same instructions.
  if (!systemEl.value.trim()) systemEl.value = hooks.getSidebarSystemPrompt?.() ?? '';
  setRunning(true);
  controller = new AbortController();
  replyEl.value = '';
  try {
    const { reply } = await streamChat({
      model,
      options: getOptions(),
      messages: buildMessages(systemEl.value.trim(), [{ role: 'user', content: questionEl.value.trim() }]),
      signal: controller.signal,
      onToken: (t) => (replyEl.value = t),
    });
    replyEl.value = reply;
  } catch (err) {
    if (err.name !== 'AbortError') errorEl.textContent = err.message;
  } finally {
    controller = null;
    setRunning(false);
  }
}

// ---- Judging ----

async function judge(times) {
  errorEl.textContent = '';
  const payload = {
    model: modelSelect.value,
    rubric: rubricEl.value.trim(),
    question: questionEl.value.trim(),
    systemPrompt: systemEl.value.trim(),
    reply: replyEl.value.trim(),
  };
  if (!payload.rubric) return (errorEl.textContent = 'Write a rubric (or pick a preset) first.');
  if (!payload.reply) return (errorEl.textContent = 'There is no reply to judge yet.');
  if (activeExercise && !prediction.verdict) return (errorEl.textContent = 'Make your own prediction first (Pass or Fail), then judge.');

  const label = activeExercise?.title ?? RUBRIC_PRESETS.find((p) => p.id === presetSelect.value)?.name ?? 'Custom rubric';
  const exercise = activeExercise;
  const cards = h('div', { class: 'judge-grid' });
  const summary = h('p', { class: 'summary', 'data-testid': 'judge-summary' });
  resultsEl.replaceChildren(summary, cards);
  setRunning(true);
  controller = new AbortController();

  const verdicts = [];
  for (let i = 0; i < times; i++) {
    const card = h('div', { class: 'card judge-result pending' }, `⏳ Judging${times > 1 ? ` ${i + 1}/${times}` : ''}… (${payload.model} usually takes 5–15s)`);
    cards.append(card);
    try {
      const v = await fetchJson('/api/judge', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
      verdicts.push(v);
      card.replaceWith(renderVerdict(v, times > 1 ? `Run ${i + 1}` : null));
      history.unshift({ time: new Date(), label, ...v });
      renderHistory();
    } catch (err) {
      card.replaceWith(h('div', { class: 'card judge-result' },
        h('p', { class: 'error-text' }, err.name === 'AbortError' ? 'Stopped.' : err.message)));
      if (err.name === 'AbortError') break;
    }
  }
  controller = null;
  setRunning(false);

  if (times > 1 && verdicts.length > 1) summary.textContent = consistencySummary(verdicts);
  if (exercise && verdicts.length) finishExercise(exercise, verdicts[0]);
}

function renderVerdict(v, title) {
  const pass = v.verdict === 'pass';
  return h('div', { class: `card judge-result ${v.verdict}`, 'data-testid': 'judge-verdict' },
    title && h('div', { class: 'muted small' }, title),
    h('div', { class: 'row' },
      h('span', { class: `badge big ${pass ? 'pass' : 'fail'}` }, pass ? '✅ PASS' : '❌ FAIL'),
      h('span', { class: 'score', 'data-testid': 'judge-score' }, `${v.score}/5`),
      h('span', { class: 'muted small' }, formatMeta(v))),
    h('ul', { class: 'criteria' }, (v.criteria ?? []).map((c) =>
      h('li', {}, `${c.met ? '✅' : '❌'} `, h('strong', {}, c.criterion), c.comment && h('span', { class: 'muted' }, `: ${c.comment}`)))),
    h('p', {}, v.reason),
  );
}

function formatMeta(v) {
  return [
    v.model,
    v.durationMs != null ? `${(v.durationMs / 1000).toFixed(1)}s` : null,
    v.costUsd != null ? `$${v.costUsd.toFixed(4)}` : null,
  ].filter(Boolean).join(' · ');
}

function consistencySummary(verdicts) {
  const passes = verdicts.filter((v) => v.verdict === 'pass').length;
  const majority = passes * 2 >= verdicts.length ? passes : verdicts.length - passes;
  const scores = verdicts.map((v) => v.score);
  const spread = Math.max(...scores) - Math.min(...scores);
  const base = `Verdict consistent ${majority}/${verdicts.length} · scores ${scores.join(', ')} (spread ${spread})`;
  if (majority < verdicts.length) {
    return `⚠️ ${base}. The judge disagreed with itself. Automated graders are non-deterministic too; use several runs or a tighter rubric.`;
  }
  return spread > 1
    ? `${base}. Same verdict, but the scores moved a lot. Don't rely on exact scores.`
    : `✅ ${base}. Stable for this case.`;
}

// ---- Judge the judge ----

function loadExercise(ex) {
  activeExercise = ex;
  prediction = { verdict: null, score: '' };
  presetSelect.value = '';
  rubricEl.value = ex.rubric;
  questionEl.value = ex.question;
  systemEl.value = ex.systemPrompt;
  replyEl.value = ex.reply;
  resultsEl.replaceChildren();
  errorEl.textContent = '';
  renderExercises();
}

function exitExercise() {
  activeExercise = null;
  renderExercises();
}

function finishExercise(ex, v) {
  progress[ex.id] = { mine: prediction.verdict, myScore: prediction.score, judge: v.verdict, judgeScore: v.score, expected: ex.expected };
  save('judge-exercises', progress);
  const judgeRight = v.verdict === ex.expected;
  const youRight = prediction.verdict === ex.expected;
  resultsEl.prepend(h('div', { class: 'card compare', 'data-testid': 'judge-compare' },
    h('h3', {}, 'You vs the judge'),
    h('table', { class: 'compare-table' },
      h('tr', {}, h('th', {}, ''), h('th', {}, 'Verdict'), h('th', {}, 'Score'), h('th', {}, '')),
      h('tr', {}, h('td', {}, 'You'), h('td', {}, prediction.verdict.toUpperCase()), h('td', {}, prediction.score || 'n/a'), h('td', {}, youRight ? '✅' : '❌')),
      h('tr', {}, h('td', {}, 'Judge'), h('td', {}, v.verdict.toUpperCase()), h('td', {}, `${v.score}/5`), h('td', {}, judgeRight ? '✅' : '❌')),
      h('tr', {}, h('td', {}, 'Expected'), h('td', {}, ex.expected.toUpperCase()), h('td', {}, ''), h('td', {}, ''))),
    h('p', {}, h('strong', {}, judgeRight ? 'The judge got this one right. ' : '⚠️ The judge got this one wrong. '), ex.lesson),
    !judgeRight && h('p', { class: 'hint' }, 'A judge mistake like this is a finding in itself. In a real project you would tighten the rubric, try a stronger judge model, or keep a human review step for this kind of case.'),
  ));
  renderExercises();
}

function renderExercises() {
  const done = EXERCISES.filter((e) => progress[e.id]);
  const judgeCorrect = done.filter((e) => progress[e.id].judge === e.expected).length;
  const youCorrect = done.filter((e) => progress[e.id].mine === e.expected).length;

  const verdictBtn = (value, label) => h('button', {
    class: prediction.verdict === value ? 'primary' : '',
    'data-testid': `predict-${value}`,
    'aria-pressed': String(prediction.verdict === value),
    onClick: () => { prediction.verdict = value; renderExercises(); },
  }, label);
  const scoreSelect = h('select', {
    value: prediction.score, 'data-testid': 'predict-score', 'aria-label': 'Your score',
    onChange: (e) => (prediction.score = e.target.value),
  }, h('option', { value: '' }, 'Score (optional)'), [5, 4, 3, 2, 1].map((n) => h('option', { value: String(n) }, `${n}/5`)));

  exercisesEl.replaceChildren(h('details', { class: 'card', open: true },
    h('summary', {}, h('h3', { class: 'inline-heading' }, 'Judge the judge'),
      h('span', { class: 'muted small', 'data-testid': 'exercise-progress' },
        ` ${done.length} of ${EXERCISES.length} done`,
        done.length ? ` · you were right ${youCorrect}/${done.length} · the judge was right ${judgeCorrect}/${done.length}` : '')),
    h('p', { class: 'hint' }, "Each exercise loads a tricky reply. Decide your own verdict first, then see whether the judge agrees with you and with the expected answer."),
    h('div', { class: 'exercise-list' }, EXERCISES.map((ex) =>
      h('button', {
        class: `exercise ${activeExercise?.id === ex.id ? 'active' : ''}`,
        'data-testid': `exercise-${ex.id}`,
        onClick: () => loadExercise(ex),
      }, progress[ex.id] ? `✓ ${ex.title}` : ex.title))),
    activeExercise && h('div', { class: 'predict', 'data-testid': 'predict-panel' },
      h('p', {}, h('strong', {}, `Exercise: ${activeExercise.title}. `), 'Read the rubric and reply below. What should the verdict be?'),
      h('div', { class: 'row' }, verdictBtn('pass', '✅ Pass'), verdictBtn('fail', '❌ Fail'), scoreSelect,
        h('button', { class: 'link', onClick: exitExercise }, 'Exit exercise'))),
  ));
}

// ---- History ----

function renderHistory() {
  if (history.length === 0) return historyEl.replaceChildren();
  const total = history.reduce((sum, v) => sum + (v.costUsd ?? 0), 0);
  historyEl.replaceChildren(h('section', { class: 'card' },
    h('h3', {}, 'History (this session)'),
    h('div', { class: 'table-wrap' }, h('table', { class: 'tc-table', 'data-testid': 'judge-history' },
      h('thead', {}, h('tr', {}, ['Time', 'Rubric', 'Verdict', 'Score', 'Model', 'Cost'].map((t) => h('th', {}, t)))),
      h('tbody', {}, history.map((v) => h('tr', {},
        h('td', {}, v.time.toLocaleTimeString()),
        h('td', {}, v.label),
        h('td', {}, h('span', { class: `badge ${v.verdict === 'pass' ? 'pass' : 'fail'}` }, v.verdict.toUpperCase())),
        h('td', {}, `${v.score}/5`),
        h('td', {}, v.model),
        h('td', {}, v.costUsd != null ? `$${v.costUsd.toFixed(4)}` : 'n/a')))))),
    h('p', { class: 'hint' }, `${history.length} judgement(s) · total about $${total.toFixed(4)}`),
  ));
}
