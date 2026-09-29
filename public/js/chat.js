import { streamChat, buildMessages } from './api.js';
import { openFlagForm } from './flags.js';
import { runVariants } from './rerun.js';
import { describeOptions } from './settings.js';
import { $, h } from './util.js';

const chatEl = $('chat');
const promptEl = $('prompt');
const sendBtn = $('send-btn');
const stopBtn = $('stop-btn');
const EMPTY_TEXT = 'Pick a model and ask something.';

// Each message: { role: 'user'|'assistant'|'error', content, context, meta?, flag?, failed?, el }
let messages = [];
let controller = null;
let hooks = {};

export function initChat(chatHooks) {
  hooks = chatHooks;
  $('chat-form').addEventListener('submit', (e) => {
    e.preventDefault();
    const text = promptEl.value.trim();
    if (!text || controller) return;
    promptEl.value = '';
    send(text);
  });
  promptEl.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      $('chat-form').requestSubmit();
    }
  });
  stopBtn.addEventListener('click', () => controller?.abort());
  clearChat();
}

export const getMessages = () => messages;
export const hasMessages = () => messages.length > 0;

export function clearChat() {
  controller?.abort();
  messages = [];
  chatEl.replaceChildren(h('p', { class: 'empty' }, EMPTY_TEXT));
}

export function insertPrompt(text) {
  promptEl.value = text;
  promptEl.focus();
}

// The turns sent to the model: everything before index, minus errors and failed sends.
export function conversation(upTo = messages.length) {
  return messages
    .slice(0, upTo)
    .filter((m) => (m.role === 'user' && !m.failed) || (m.role === 'assistant' && m.content))
    .map(({ role, content }) => ({ role, content }));
}

function addMessage(msg) {
  if (messages.length === 0) chatEl.replaceChildren();
  messages.push(msg);
  const bubble = h('div', { class: 'bubble' }, msg.content);
  const meta = h('div', { class: 'meta' });
  const actions = h('div', { class: 'actions' });
  const flagArea = h('div', { class: 'flag-area' });
  const variantsArea = h('div', { class: 'variants-area' });
  const wrap = h('div', { class: `msg ${msg.role}`, 'data-testid': `message-${msg.role}` },
    bubble, meta, actions, flagArea, variantsArea);
  msg.el = { wrap, bubble, meta, actions, flagArea, variantsArea };
  chatEl.append(wrap);
  scrollToBottom();
  return msg;
}

function removeMessage(msg) {
  messages = messages.filter((m) => m !== msg);
  msg.el.wrap.remove();
}

function renderActions(msg) {
  const { actions } = msg.el;
  actions.replaceChildren();
  if (msg.role === 'user') {
    actions.append(h('button', {
      class: 'link', 'data-testid': 'save-as-testcase',
      onClick: () => hooks.onSaveAsTestCase?.({ prompt: msg.content, ...msg.context }),
    }, '＋ Save as test case'));
  }
  if (msg.role === 'assistant') {
    actions.append(
      h('button', { class: 'link', 'data-testid': 'flag-reply', onClick: () => openFlagForm(msg) }, '⚑ Flag'),
      h('button', {
        class: 'link', 'data-testid': 'rerun-reply',
        onClick: (e) => runVariants({
          msg,
          button: e.currentTarget,
          messages: buildMessages(msg.context.systemPrompt, conversation(messages.indexOf(msg))),
          onVerdict: hooks.onVerdict,
        }),
      }, '↻ Run ×5'),
    );
  }
}

function scrollToBottom() {
  chatEl.scrollTop = chatEl.scrollHeight;
}

function setBusy(busy) {
  sendBtn.hidden = busy;
  stopBtn.hidden = !busy;
  promptEl.disabled = busy;
  hooks.onBusyChange?.(busy);
}

async function send(text) {
  const ctx = hooks.getContext();
  if (!ctx.model) return addMessage({ role: 'error', content: 'No model selected.' });

  const user = addMessage({ role: 'user', content: text, context: ctx });
  renderActions(user);
  const reply = addMessage({ role: 'assistant', content: '', context: ctx });
  reply.el.bubble.classList.add('streaming');
  setBusy(true);
  const myController = (controller = new AbortController());
  const started = performance.now();

  try {
    const result = await streamChat({
      model: ctx.model,
      botId: ctx.botId,
      options: ctx.options,
      messages: buildMessages(ctx.systemPrompt, conversation(messages.indexOf(reply))),
      signal: myController.signal,
      onToken: (t) => {
        reply.content = t;
        reply.el.bubble.textContent = t;
        scrollToBottom();
      },
    });
    reply.content = result.reply;
    reply.el.bubble.textContent = result.reply;
    reply.meta = formatMeta(ctx, started, result.stats, result.verdict);
    if (result.verdict) hooks.onVerdict?.(result.verdict, ctx);
  } catch (err) {
    if (err.name === 'AbortError') {
      reply.meta = `${formatMeta(ctx, started)} · stopped`;
    } else {
      removeMessage(reply);
      user.failed = true; // excluded from history so the question can be retried
      addMessage({ role: 'error', content: err.message });
    }
  } finally {
    reply.el.bubble.classList.remove('streaming');
    reply.el.meta.textContent = reply.meta ?? '';
    renderActions(reply);
    if (controller === myController) {
      controller = null;
      setBusy(false);
      promptEl.focus();
    }
  }
}

function formatMeta(ctx, started, stats, verdict) {
  const secs = ((performance.now() - started) / 1000).toFixed(2);
  const parts = [ctx.model, `${secs}s`];
  if (stats?.eval_count && stats?.eval_duration) {
    const tps = stats.eval_count / (stats.eval_duration / 1e9);
    parts.push(`${stats.eval_count} tokens`, `${tps.toFixed(1)} tok/s`);
  }
  parts.push(describeOptions(ctx.options));
  if (verdict?.blocked) parts.push(`🛡 blocked by ${verdict.blocked} filter`);
  return parts.join(' · ');
}
