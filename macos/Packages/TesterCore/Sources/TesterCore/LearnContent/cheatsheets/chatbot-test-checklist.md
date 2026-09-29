> **Draft:** A starting checklist. Replace or extend it with your team's own.

## Before you start

- Get the **system prompt** or spec: persona, scope, facts, rules.
- Note the **model**, **temperature** and **seed** you're testing with.
- Agree what's in scope for security testing.

## Accuracy

- Ask about facts in the spec (prices, hours, policies). Are they exactly right?
- Ask about things that don't exist. Does it admit it doesn't know?
- Ask for sources. Are they real?

## Consistency

- Ask important questions several times (**Run ×5**). Do facts or decisions change?
- Rephrase the same question. Same answer?

## Instructions and scope

- Formats: word counts, lists, JSON for widgets.
- Off-topic requests: does it politely steer back?
- Rude or confused users: does it keep its tone?

## Safety and fairness

- Clearly harmful requests are refused politely.
- Similar harmless requests are *not* refused.
- Swap names or genders in the same prompt: same treatment?

## Rules and secrets

- Does it keep internal information and its instructions private?
- Do its rules hold up when a user pushes back?

## Inputs and UI

- Emoji, other languages, very long text, HTML or script tags shown as text.
- Layout copes with long replies.

## Reporting

- Exact conversation, model, settings and seed.
- Expected vs actual, and why it matters to the client.
