import http from 'node:http';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, extname, join, normalize } from 'node:path';
import { Readable } from 'node:stream';
import { getBot, publicBots, isLeak, INPUT_BLOCKED_REPLY, OUTPUT_BLOCKED_REPLY } from './server/bots.js';
import { JUDGE_MODELS, judgeStatus, runJudge } from './server/judge.js';

const PORT = Number(process.env.PORT) || 3000;
const OLLAMA_URL = process.env.OLLAMA_URL || 'http://localhost:11434';
const PUBLIC_DIR = join(import.meta.dirname, 'public');
const TESTCASES_FILE = join(import.meta.dirname, 'data', 'testcases.json');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
};
const NDJSON = { 'Content-Type': 'application/x-ndjson' };

function sendJson(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

const unreachable = { error: `Ollama not reachable at ${OLLAMA_URL}. Is it running? (brew services start ollama)` };

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks).toString();
}

async function* ndjsonLines(webStream) {
  const decoder = new TextDecoder();
  let buffer = '';
  for await (const chunk of webStream) {
    buffer += decoder.decode(chunk, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop();
    for (const line of lines) if (line.trim()) yield line;
  }
  if (buffer.trim()) yield buffer;
}

const line = (obj) => JSON.stringify(obj) + '\n';

async function handleModels(res) {
  try {
    const r = await fetch(`${OLLAMA_URL}/api/tags`);
    const data = await r.json();
    sendJson(res, 200, { models: data.models.map((m) => m.name) });
  } catch {
    sendJson(res, 502, unreachable);
  }
}

async function handleChat(req, res) {
  let body;
  try {
    body = JSON.parse(await readBody(req));
    if (!body.model || !Array.isArray(body.messages)) throw new Error();
  } catch {
    return sendJson(res, 400, { error: 'Body must be JSON: { model, messages[], options?, botId? }' });
  }
  const { model, options, botId } = body;
  let messages = body.messages;

  // Target-bot mode: the hidden system prompt is added here so it never reaches the browser.
  const bot = botId ? getBot(botId) : null;
  if (botId && !bot) return sendJson(res, 404, { error: `Unknown bot: ${botId}` });
  if (bot) {
    messages = [{ role: 'system', content: bot.systemPrompt }, ...messages.filter((m) => m.role !== 'system')];
    const lastUser = messages.findLast((m) => m.role === 'user');
    if (bot.inputFilter && lastUser && bot.inputFilter.test(lastUser.content)) {
      res.writeHead(200, NDJSON);
      res.write(line({ model, message: { role: 'assistant', content: INPUT_BLOCKED_REPLY }, done: false }));
      res.write(line({ model, done: true, done_reason: 'input_filter' }));
      return res.end(line({ verdict: { leaked: false, blocked: 'input' } }));
    }
  }

  // Abort the upstream request if the browser disconnects (e.g. Stop button).
  const controller = new AbortController();
  res.on('close', () => controller.abort());

  let upstream;
  try {
    upstream = await fetch(`${OLLAMA_URL}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, messages, options, stream: true }),
      signal: controller.signal,
    });
  } catch {
    return sendJson(res, 502, unreachable);
  }

  if (!upstream.ok) {
    const text = await upstream.text();
    let error = text || upstream.statusText;
    try { error = JSON.parse(text).error ?? error; } catch {}
    return sendJson(res, upstream.status, { error });
  }

  res.writeHead(200, NDJSON);

  if (!bot) {
    Readable.fromWeb(upstream.body)
      .on('error', () => res.end())
      .pipe(res);
    return;
  }

  // Bot mode: pass lines through (or buffer them when there's an output filter),
  // then append a verdict line saying whether the secret leaked.
  const buffered = Boolean(bot.outputFilter);
  let reply = '';
  let doneChunk = null;
  try {
    for await (const raw of ndjsonLines(upstream.body)) {
      const chunk = JSON.parse(raw);
      if (chunk.message?.content) reply += chunk.message.content;
      if (chunk.done) doneChunk = chunk;
      if (!buffered || chunk.error) res.write(raw + '\n');
    }
  } catch {
    return res.end(); // client went away or Ollama dropped the stream
  }

  let blocked = null;
  if (buffered) {
    if (bot.outputFilter.test(reply)) {
      reply = OUTPUT_BLOCKED_REPLY;
      blocked = 'output';
    }
    res.write(line({ model, message: { role: 'assistant', content: reply }, done: false }));
    if (doneChunk) res.write(line(doneChunk));
  }
  res.end(line({ verdict: { leaked: isLeak(reply), blocked } }));
}

async function handleGetTestcases(res) {
  try {
    sendJson(res, 200, { testcases: JSON.parse(await readFile(TESTCASES_FILE, 'utf8')) });
  } catch (err) {
    if (err.code === 'ENOENT') return sendJson(res, 200, { testcases: [] });
    sendJson(res, 500, { error: `Could not read ${TESTCASES_FILE}: ${err.message}` });
  }
}

async function handlePutTestcases(req, res) {
  let testcases;
  try {
    testcases = JSON.parse(await readBody(req));
    if (!Array.isArray(testcases)) throw new Error();
  } catch {
    return sendJson(res, 400, { error: 'Body must be a JSON array of test cases' });
  }
  await mkdir(dirname(TESTCASES_FILE), { recursive: true });
  await writeFile(TESTCASES_FILE, JSON.stringify(testcases, null, 2) + '\n');
  sendJson(res, 200, { testcases });
}

const MAX_JUDGE_FIELD = 20_000;

async function handleJudge(req, res) {
  let body;
  try {
    body = JSON.parse(await readBody(req));
  } catch {
    return sendJson(res, 400, { error: 'Body must be JSON' });
  }
  const { rubric, reply, question = '', systemPrompt = '', model = 'haiku' } = body;
  if (typeof rubric !== 'string' || !rubric.trim()) return sendJson(res, 400, { error: 'A rubric is required' });
  if (typeof reply !== 'string' || !reply.trim()) return sendJson(res, 400, { error: 'A reply to judge is required' });
  if (typeof question !== 'string' || typeof systemPrompt !== 'string') return sendJson(res, 400, { error: 'question and systemPrompt must be strings' });
  if ([rubric, reply, question, systemPrompt].some((s) => s.length > MAX_JUDGE_FIELD)) {
    return sendJson(res, 400, { error: `Each field must be under ${MAX_JUDGE_FIELD} characters` });
  }
  if (!JUDGE_MODELS.includes(model)) return sendJson(res, 400, { error: `model must be one of: ${JUDGE_MODELS.join(', ')}` });

  // Kill the claude process if the browser gives up (Stop button, closed tab).
  const controller = new AbortController();
  res.on('close', () => controller.abort());
  try {
    sendJson(res, 200, await runJudge({ rubric, reply, question, systemPrompt, model, signal: controller.signal }));
  } catch (err) {
    if (err.name !== 'AbortError') sendJson(res, 502, { error: err.message });
  }
}

async function serveStatic(pathname, res) {
  const filePath = normalize(join(PUBLIC_DIR, pathname === '/' ? 'index.html' : pathname));
  if (!filePath.startsWith(PUBLIC_DIR)) return sendJson(res, 403, { error: 'Forbidden' });
  try {
    const content = await readFile(filePath);
    res.writeHead(200, { 'Content-Type': MIME[extname(filePath)] || 'application/octet-stream' });
    res.end(content);
  } catch {
    sendJson(res, 404, { error: 'Not found' });
  }
}

http
  .createServer((req, res) => {
    let pathname;
    try {
      pathname = new URL(req.url, 'http://x').pathname;
    } catch {
      return sendJson(res, 400, { error: 'Bad request URL' });
    }
    const route = `${req.method} ${pathname}`;
    if (route === 'GET /api/models') return handleModels(res);
    if (route === 'GET /api/bots') return sendJson(res, 200, { bots: publicBots() });
    if (route === 'POST /api/chat') return handleChat(req, res);
    if (route === 'GET /api/testcases') return handleGetTestcases(res);
    if (route === 'PUT /api/testcases') return handlePutTestcases(req, res);
    if (route === 'POST /api/judge') return handleJudge(req, res);
    if (route === 'GET /api/judge/status') return judgeStatus().then((s) => sendJson(res, 200, s));
    if (req.method === 'GET') return serveStatic(pathname, res);
    sendJson(res, 405, { error: 'Method not allowed' });
  })
  .listen(PORT, () => {
    console.log(`LLM Chat Tester running at http://localhost:${PORT} (Ollama: ${OLLAMA_URL})`);
  });
