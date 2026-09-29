// Pure checks used by the test-case runner. No DOM access, so they can be tested in Node.

export const ASSERTION_TYPES = {
  contains: 'Contains',
  not_contains: "Doesn't contain",
  regex: 'Matches regex',
  max_length: 'Max length (chars)',
  min_length: 'Min length (chars)',
};

export function checkAssertion({ type, value, caseSensitive }, reply) {
  const text = reply.trim();
  const norm = (s) => (caseSensitive ? s : s.toLowerCase());
  switch (type) {
    case 'contains':
      return { pass: norm(text).includes(norm(value)) };
    case 'not_contains':
      return { pass: !norm(text).includes(norm(value)) };
    case 'regex':
      try {
        return { pass: new RegExp(value, caseSensitive ? '' : 'i').test(text) };
      } catch {
        return { pass: false, detail: 'Invalid regex' };
      }
    case 'max_length':
      return { pass: text.length <= Number(value), detail: `${text.length} chars` };
    case 'min_length':
      return { pass: text.length >= Number(value), detail: `${text.length} chars` };
    default:
      return { pass: false, detail: `Unknown check: ${type}` };
  }
}

export function describeAssertion({ type, value, caseSensitive }) {
  const label = ASSERTION_TYPES[type] ?? type;
  const quoted = type.endsWith('_length') ? value : `"${value}"`;
  return `${label} ${quoted}${caseSensitive ? ' (case-sensitive)' : ''}`;
}
