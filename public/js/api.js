export async function fetchJson(url, opts) {
  const res = await fetch(url, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || res.statusText);
  return data;
}

export function buildMessages(systemPrompt, conversation) {
  return systemPrompt ? [{ role: 'system', content: systemPrompt }, ...conversation] : conversation;
}

// Streams a chat reply from the server. Calls onToken(replySoFar) as text arrives.
// Resolves with { reply, stats, verdict } — verdict is only present in target-bot mode.
export async function streamChat({ model, messages, options, botId, signal, onToken }) {
  const res = await fetch('/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, messages, options, botId }),
    signal,
  });
  if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || res.statusText);

  // The server streams newline-delimited JSON objects.
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let reply = '';
  let stats = null;
  let verdict = null;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop();
    for (const line of lines) {
      if (!line.trim()) continue;
      const chunk = JSON.parse(line);
      if (chunk.error) throw new Error(chunk.error);
      if (chunk.verdict) verdict = chunk.verdict;
      if (chunk.message?.content) {
        reply += chunk.message.content;
        onToken?.(reply);
      }
      if (chunk.done) stats = chunk;
    }
  }
  return { reply, stats, verdict };
}
