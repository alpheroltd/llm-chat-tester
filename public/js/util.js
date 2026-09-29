export const $ = (id) => document.getElementById(id);

// Tiny DOM builder: h('button', { class: 'x', onClick: fn, 'data-testid': 'y' }, 'Label').
// Text children are always inserted as text, never HTML.
export function h(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  const deferred = {};
  for (const [key, value] of Object.entries(props ?? {})) {
    if (value == null || value === false) continue;
    if (key.startsWith('on')) node.addEventListener(key.slice(2).toLowerCase(), value);
    else if (key === 'class') node.className = value;
    else if (key === 'value' || key === 'checked') deferred[key] = value;
    else node.setAttribute(key, value === true ? '' : value);
  }
  for (const child of children.flat()) {
    if (child == null || child === false) continue;
    node.append(child instanceof Node ? child : String(child));
  }
  Object.assign(node, deferred); // after children so <select>/<textarea> values stick
  return node;
}

export function load(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw == null ? fallback : JSON.parse(raw);
  } catch {
    return fallback;
  }
}

export function save(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // storage unavailable (private window etc.) — progress just won't persist
  }
}

export function downloadFile(filename, text, type = 'text/markdown') {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = h('a', { href: url, download: filename });
  document.body.append(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
