import { CATEGORIES } from '../data/missions.js';
import { describeOptions } from './settings.js';
import { downloadFile, h } from './util.js';

const SEVERITIES = ['Low', 'Medium', 'High', 'Critical'];
let formCount = 0;

// Inline form under an assistant reply to record a pass/fail verdict.
export function openFlagForm(msg) {
  const existing = msg.flag ?? { verdict: 'fail', category: CATEGORIES[0], severity: 'Medium', expected: '', note: '' };
  const name = `verdict-${++formCount}`;
  const radio = (value, label) =>
    h('label', { class: 'inline' },
      h('input', { type: 'radio', name, value, checked: existing.verdict === value, 'data-testid': `flag-${value}` }), label);
  const select = (options, value, testid) =>
    h('select', { value, 'data-testid': testid }, options.map((o) => h('option', { value: o }, o)));

  const category = select(CATEGORIES, existing.category, 'flag-category');
  const severity = select(SEVERITIES, existing.severity, 'flag-severity');
  const expected = h('textarea', { rows: 2, value: existing.expected, placeholder: 'What should the bot have done?', 'data-testid': 'flag-expected' });
  const note = h('textarea', { rows: 2, value: existing.note, placeholder: 'What went wrong / why it passes', 'data-testid': 'flag-note' });

  const form = h('form', { class: 'flag-form', 'data-testid': 'flag-form' },
    h('div', { class: 'row' }, radio('fail', '❌ Fail (bug)'), radio('pass', '✅ Pass')),
    h('div', { class: 'row' }, h('label', {}, 'Category ', category), h('label', {}, 'Severity ', severity)),
    h('label', { class: 'block' }, 'Expected behaviour', expected),
    h('label', { class: 'block' }, 'Notes', note),
    h('div', { class: 'row' },
      h('button', { type: 'submit', class: 'primary', 'data-testid': 'flag-save' }, 'Save flag'),
      h('button', { type: 'button', onClick: () => renderFlag(msg) }, 'Cancel'),
      msg.flag && h('button', { type: 'button', onClick: () => { msg.flag = null; renderFlag(msg); } }, 'Remove flag'),
    ),
  );
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    msg.flag = {
      verdict: form.querySelector(`input[name="${name}"]:checked`).value,
      category: category.value,
      severity: severity.value,
      expected: expected.value.trim(),
      note: note.value.trim(),
    };
    renderFlag(msg);
  });
  msg.el.flagArea.replaceChildren(form);
}

function renderFlag(msg) {
  const { wrap, flagArea } = msg.el;
  wrap.classList.remove('flag-pass', 'flag-fail');
  if (!msg.flag) return flagArea.replaceChildren();
  const f = msg.flag;
  wrap.classList.add(`flag-${f.verdict}`);
  flagArea.replaceChildren(
    h('div', { class: 'flag-summary', 'data-testid': 'flag-summary' },
      f.verdict === 'fail' ? `❌ ${f.severity} · ${f.category}` : `✅ Pass · ${f.category}`,
      f.note && h('span', { class: 'muted' }, ` · ${f.note}`),
      ' ', h('button', { class: 'link', onClick: () => openFlagForm(msg) }, 'edit')),
  );
}

// ---- Markdown report ----

const quote = (text) => (text || '(empty)').split('\n').map((l) => `> ${l}`).join('\n');
const fence = (text) => '```\n' + text + '\n```';

function describeTarget(ctx) {
  if (ctx.botId) return '(hidden: target bot)';
  return ctx.systemPrompt ? 'see below' : '(none)';
}

export function buildReport(messages) {
  const chat = messages.filter((m) => m.role !== 'error');
  const ctx = chat[0]?.context ?? {};
  const flagged = chat.filter((m) => m.flag);
  const fails = flagged.filter((m) => m.flag.verdict === 'fail');
  const passes = flagged.filter((m) => m.flag.verdict === 'pass');
  const out = [];

  out.push('# Chatbot test session report', '');
  out.push(`- **Date:** ${new Date().toLocaleString()}`);
  out.push(`- **Model:** \`${ctx.model}\``);
  out.push(`- **Mode:** ${ctx.modeLabel}`);
  out.push(`- **Settings:** ${ctx.options ? describeOptions(ctx.options) : 'n/a'}`);
  out.push(`- **System prompt:** ${describeTarget(ctx)}`);
  out.push(`- **Result:** ${fails.length} issue(s) found, ${passes.length} check(s) passed, ${chat.filter((m) => m.role === 'user').length} message(s) sent`);
  out.push('');
  if (ctx.systemPrompt) out.push('## System prompt', '', fence(ctx.systemPrompt), '');

  out.push('## Issues', '');
  if (fails.length === 0) out.push('_No issues flagged._', '');
  fails.forEach((m, i) => {
    const f = m.flag;
    const idx = chat.indexOf(m);
    const userTurns = chat.slice(0, idx).filter((x) => x.role === 'user');
    out.push(`### ${i + 1}. [${f.severity}] ${f.category}${f.note ? `: ${f.note.split('\n')[0]}` : ''}`, '');
    out.push('**Steps to reproduce**', '');
    out.push(`1. Model \`${m.context.model}\`, ${describeOptions(m.context.options)}, mode: ${m.context.modeLabel}`);
    if (m.context.systemPrompt) out.push('2. Set the system prompt shown above');
    userTurns.forEach((u, n) => out.push(`${n + (m.context.systemPrompt ? 3 : 2)}. Send: "${u.content.replace(/\n/g, ' ')}"`));
    out.push('');
    out.push(`**Expected:** ${f.expected || '_not specified_'}`, '');
    out.push('**Actual:**', '', quote(m.content), '');
    if (f.note) out.push(`**Notes:** ${f.note}`, '');
    out.push(`_Reply meta: ${m.meta ?? ''}_`, '');
  });

  if (passes.length) {
    out.push('## Passed checks', '');
    passes.forEach((m) => out.push(`- **${m.flag.category}**: ${m.flag.note || m.content.slice(0, 80).replace(/\n/g, ' ')}`));
    out.push('');
  }

  out.push('## Full transcript', '');
  chat.forEach((m) => {
    const tag = m.flag ? (m.flag.verdict === 'fail' ? ' ❌' : ' ✅') : '';
    out.push(m.role === 'user' ? '**User:**' : `**Assistant**${tag} _(${m.meta ?? ''})_:`, '', quote(m.content), '');
  });

  return out.join('\n');
}

export function exportReport(messages) {
  const stamp = new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-');
  downloadFile(`chatbot-test-report-${stamp}.md`, buildReport(messages));
}
