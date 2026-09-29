import { streamChat } from './api.js';
import { describeOptions, getOptions } from './settings.js';
import { h } from './util.js';

const RUNS = 5;

// Re-sends the same conversation RUNS times and lists the answers, without touching chat history.
// Uses the message's model/bot/system prompt but the *current* settings, so learners can
// change temperature/seed and compare.
export async function runVariants({ msg, button, messages, onVerdict }) {
  const ctx = msg.context;
  const options = getOptions();
  const summary = h('summary', {}, `Re-running 0/${RUNS}…`);
  const list = h('ol', { class: 'variants' });
  const tip = h('p', { class: 'hint' });
  msg.el.variantsArea.replaceChildren(
    h('details', { class: 'variants-panel', open: true, 'data-testid': 'variants' }, summary, list, tip),
  );
  button.disabled = true;

  const replies = [];
  for (let i = 0; i < RUNS; i++) {
    const item = h('li', { class: 'pending' }, '…');
    list.append(item);
    try {
      const { reply, verdict } = await streamChat({ model: ctx.model, botId: ctx.botId, options, messages });
      replies.push(reply.trim());
      item.textContent = reply;
      if (verdict) onVerdict?.(verdict, ctx);
    } catch (err) {
      item.textContent = `Error: ${err.message}`;
      item.classList.add('error');
    }
    item.classList.remove('pending');
    summary.textContent = `Re-running ${i + 1}/${RUNS}…`;
  }

  const unique = new Set(replies).size;
  summary.textContent = `${unique} unique answer${unique === 1 ? '' : 's'} out of ${replies.length} · ${describeOptions(options)}`;
  tip.textContent = unique > 1
    ? 'Answers vary between runs. Did the meaning change, or just the wording? Try temperature 0 with a fixed seed and run again.'
    : 'Every run gave the same answer. Try a higher temperature and a blank seed to see randomness come back.';
  button.disabled = false;
}
