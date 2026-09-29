import { buildMessages, fetchJson, streamChat } from './api.js';
import { ASSERTION_TYPES, checkAssertion, describeAssertion } from './assertions.js';
import { describeOptions, getOptions } from './settings.js';
import { $, h } from './util.js';

const tableEl = $('tc-table');
const editorEl = $('tc-editor');
const summaryEl = $('tc-summary');
const runBtn = $('tc-run');
const stopBtn = $('tc-stop');
const runsEl = $('tc-runs');

let cases = [];
const results = new Map(); // case id → { status, runs: [{ reply, checks, pass, ms, error? }] }
let editing = null;
let running = false;
let controller = null;
let hooks = {};

export async function initTestCases(tcHooks) {
  hooks = tcHooks;
  $('tc-new').addEventListener('click', () => openEditor());
  runBtn.addEventListener('click', () => runCases(cases));
  stopBtn.addEventListener('click', () => {
    running = false;
    controller?.abort();
  });
  try {
    cases = (await fetchJson('/api/testcases')).testcases;
  } catch (err) {
    summaryEl.textContent = `Could not load test cases: ${err.message}`;
  }
  renderTable();
}

async function persist() {
  await fetchJson('/api/testcases', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(cases),
  });
}

function targetLabel(tc) {
  if (tc.botId) return hooks.getBots().find((b) => b.id === tc.botId)?.name ?? tc.botId;
  return tc.systemPrompt ? 'Custom system prompt' : 'No system prompt';
}

// ---- Editor ----

export function openEditor(prefill = {}) {
  editing = {
    id: prefill.id ?? null,
    name: prefill.name ?? '',
    prompt: prefill.prompt ?? '',
    systemPrompt: prefill.systemPrompt ?? '',
    botId: prefill.botId ?? '',
    assertions: structuredClone(prefill.assertions ?? [{ type: 'contains', value: '', caseSensitive: false }]),
  };
  renderEditor();
  editorEl.scrollIntoView({ behavior: 'smooth', block: 'start' });
  editorEl.querySelector('input')?.focus();
}

function closeEditor() {
  editing = null;
  editorEl.hidden = true;
  editorEl.replaceChildren();
}

function renderEditor() {
  const e = editing;
  const bind = (key) => (ev) => { e[key] = ev.target.value; };

  const systemField = h('label', { class: 'block', hidden: Boolean(e.botId) }, 'System prompt (optional)',
    h('textarea', { rows: 3, value: e.systemPrompt, onInput: bind('systemPrompt'), 'data-testid': 'tc-system' }));

  const assertionRows = e.assertions.map((a, i) =>
    h('div', { class: 'row assertion-row', 'data-testid': 'tc-assertion' },
      h('select', { value: a.type, onChange: (ev) => { a.type = ev.target.value; } },
        Object.entries(ASSERTION_TYPES).map(([value, label]) => h('option', { value }, label))),
      h('input', { value: a.value, placeholder: 'value', onInput: (ev) => { a.value = ev.target.value; } }),
      h('label', { class: 'inline' },
        h('input', { type: 'checkbox', checked: a.caseSensitive, onChange: (ev) => { a.caseSensitive = ev.target.checked; } }),
        'case-sensitive'),
      h('button', { type: 'button', 'aria-label': 'Remove check', onClick: () => { e.assertions.splice(i, 1); renderEditor(); } }, '✕'),
    ));

  const error = h('p', { class: 'error-text' });
  const form = h('form', { class: 'card' },
    h('h3', {}, e.id ? 'Edit test case' : 'New test case'),
    h('label', { class: 'block' }, 'Name',
      h('input', { value: e.name, onInput: bind('name'), placeholder: 'e.g. States the returns policy', 'data-testid': 'tc-name' })),
    h('label', { class: 'block' }, 'Target',
      h('select', {
        value: e.botId, 'data-testid': 'tc-target',
        onChange: (ev) => { e.botId = ev.target.value; systemField.hidden = Boolean(e.botId); },
      }, h('option', { value: '' }, 'Model directly'), hooks.getBots().map((b) => h('option', { value: b.id }, b.name)))),
    systemField,
    h('label', { class: 'block' }, 'Prompt (one message)',
      h('textarea', { rows: 2, value: e.prompt, onInput: bind('prompt'), 'data-testid': 'tc-prompt' })),
    h('p', { class: 'label' }, 'Checks (all must pass)'),
    assertionRows,
    h('button', {
      type: 'button', class: 'link', 'data-testid': 'tc-add-check',
      onClick: () => { e.assertions.push({ type: 'contains', value: '', caseSensitive: false }); renderEditor(); },
    }, '＋ Add check'),
    h('p', { class: 'hint' }, 'Tip: check for key facts ("contains 30") rather than exact sentences. Exact wording changes from run to run.'),
    error,
    h('div', { class: 'row' },
      h('button', { type: 'submit', class: 'primary', 'data-testid': 'tc-save' }, 'Save'),
      h('button', { type: 'button', onClick: closeEditor }, 'Cancel')),
  );
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const assertions = e.assertions.filter((a) => a.value.trim() !== '');
    if (!e.name.trim() || !e.prompt.trim()) return (error.textContent = 'Name and prompt are required.');
    if (assertions.length === 0) return (error.textContent = 'Add at least one check with a value.');
    const tc = {
      id: e.id ?? crypto.randomUUID(),
      name: e.name.trim(),
      prompt: e.prompt.trim(),
      systemPrompt: e.botId ? '' : e.systemPrompt.trim(),
      botId: e.botId,
      assertions,
    };
    const idx = cases.findIndex((c) => c.id === tc.id);
    const updated = idx === -1 ? [...cases, tc] : cases.map((c) => (c.id === tc.id ? tc : c));
    const previous = cases;
    cases = updated;
    try {
      await persist();
      results.delete(tc.id);
      closeEditor();
      renderTable();
    } catch (err) {
      cases = previous;
      error.textContent = `Could not save: ${err.message}`;
    }
  });
  editorEl.replaceChildren(form);
  editorEl.hidden = false;
}

// ---- Table ----

function statusBadge(result) {
  if (!result) return h('span', { class: 'muted' }, '—');
  if (result.status === 'running') return h('span', { class: 'badge running' }, `⏳ ${result.runs.length} done`);
  const passed = result.runs.filter((r) => r.pass).length;
  const label = { pass: '✅ Pass', fail: '❌ Fail', flaky: '⚠️ Flaky' }[result.status];
  return h('span', { class: `badge ${result.status}`, 'data-testid': 'tc-status' },
    result.runs.length > 1 ? `${label} ${passed}/${result.runs.length}` : label);
}

function runDetails(result) {
  if (!result?.runs.length) return null;
  return h('details', { class: 'run-details' },
    h('summary', {}, 'details'),
    result.runs.map((run, i) =>
      h('div', { class: 'run' },
        h('div', { class: 'muted' }, `Run ${i + 1} · ${(run.ms / 1000).toFixed(2)}s`),
        run.error
          ? h('p', { class: 'error-text' }, run.error)
          : [
              h('ul', { class: 'checks' }, run.checks.map((c) =>
                h('li', {}, `${c.pass ? '✅' : '❌'} ${describeAssertion(c)}${c.detail ? ` (${c.detail})` : ''}`))),
              h('div', { class: 'reply' }, run.reply),
            ],
      )),
  );
}

function renderTable() {
  if (cases.length === 0) {
    tableEl.replaceChildren(h('tbody', {}, h('tr', {}, h('td', { class: 'muted' }, 'No test cases yet. Create one, or use "Save as test case" in the chat.'))));
    return;
  }
  tableEl.replaceChildren(
    h('thead', {}, h('tr', {}, ['Name', 'Target', 'Prompt', 'Checks', 'Result', ''].map((t) => h('th', {}, t)))),
    h('tbody', {}, cases.map((tc) => {
      const result = results.get(tc.id);
      return h('tr', { 'data-testid': 'tc-row' },
        h('td', {}, tc.name),
        h('td', { class: 'muted' }, targetLabel(tc)),
        h('td', { class: 'prompt-cell' }, tc.prompt),
        h('td', {}, h('ul', { class: 'checks' }, tc.assertions.map((a) => h('li', {}, describeAssertion(a))))),
        h('td', {}, statusBadge(result), runDetails(result)),
        h('td', { class: 'row-actions' },
          h('button', { class: 'link', disabled: running, onClick: () => runCases([tc]) }, '▶ Run'),
          h('button', { class: 'link', disabled: running, onClick: () => openEditor(tc) }, 'Edit'),
          h('button', {
            class: 'link danger', disabled: running,
            onClick: async () => {
              if (!confirm(`Delete "${tc.name}"?`)) return;
              cases = cases.filter((c) => c !== tc);
              results.delete(tc.id);
              await persist().catch((err) => alert(`Could not save: ${err.message}`));
              renderTable();
            },
          }, 'Delete')),
      );
    })),
  );
}

// ---- Runner ----

function setRunning(value) {
  running = value;
  runBtn.hidden = value;
  stopBtn.hidden = !value;
  renderTable();
}

async function runCases(list) {
  const model = hooks.getModel();
  if (!model) return (summaryEl.textContent = 'Select a model first.');
  if (list.length === 0) return;
  const runsPerCase = Math.min(Math.max(parseInt(runsEl.value, 10) || 1, 1), 10);
  const options = getOptions();
  const started = performance.now();
  setRunning(true);

  for (const tc of list) {
    if (!running) break;
    const result = { status: 'running', runs: [] };
    results.set(tc.id, result);
    renderTable();
    for (let i = 0; i < runsPerCase && running; i++) {
      const t0 = performance.now();
      controller = new AbortController();
      try {
        const { reply } = await streamChat({
          model,
          options,
          botId: tc.botId || undefined,
          messages: buildMessages(tc.botId ? '' : tc.systemPrompt, [{ role: 'user', content: tc.prompt }]),
          signal: controller.signal,
        });
        const checks = tc.assertions.map((a) => ({ ...a, ...checkAssertion(a, reply) }));
        result.runs.push({ reply, checks, pass: checks.every((c) => c.pass), ms: performance.now() - t0 });
      } catch (err) {
        if (err.name === 'AbortError') break;
        result.runs.push({ error: err.message, checks: [], pass: false, ms: performance.now() - t0 });
      }
      renderTable();
    }
    const passed = result.runs.filter((r) => r.pass).length;
    if (result.runs.length === 0) results.delete(tc.id);
    else result.status = passed === result.runs.length ? 'pass' : passed === 0 ? 'fail' : 'flaky';
  }

  controller = null;
  const stopped = !running;
  setRunning(false);

  const counts = { pass: 0, flaky: 0, fail: 0 };
  for (const tc of list) {
    const r = results.get(tc.id);
    if (r?.status in counts) counts[r.status]++;
  }
  const secs = ((performance.now() - started) / 1000).toFixed(1);
  summaryEl.textContent = `${stopped ? 'Stopped · ' : ''}✅ ${counts.pass} passed · ⚠️ ${counts.flaky} flaky · ❌ ${counts.fail} failed · ${model} · ${describeOptions(options)} · ${runsPerCase} run(s) per case · ${secs}s`;
}
