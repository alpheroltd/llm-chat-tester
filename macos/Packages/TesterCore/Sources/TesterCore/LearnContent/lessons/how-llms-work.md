> **Draft:** Sample lesson written to show the format. Your team's material will replace it.

A chatbot built on a large language model (LLM) feels like it *knows* things. It doesn't, at least not the way a database does. Understanding what it actually does explains most of the bugs you'll find.

## What an LLM actually does

An LLM reads the text so far and predicts a likely next **token** (a word or part of a word). It adds that token, then predicts the next one, over and over until the reply is finished.

- It's very good at producing text that *sounds* right.
- It has no built-in way to check whether that text *is* right.
- It has no memory between conversations unless the app gives it one.

> **Tip:** When a bot confidently invents an opening time or a product feature, it isn't lying. It's producing the most plausible-sounding continuation. That's why made-up facts are the most common chatbot bug.

## The system prompt: the bot's spec

Before the user types anything, the app gives the model hidden instructions called the **system prompt**. For a client's support bot it describes who the bot is, what it may talk about, and facts like prices and policies.

For testers, the system prompt is the closest thing to a specification. Every rule in it is something to test, and anything missing from it is something the bot will probably make up.

## The context window: what the bot can "remember"

Each time the user sends a message, the app sends the model the system prompt **plus the whole conversation so far**. That bundle is the **context window**, and it has a size limit.

1. Short conversations: the model sees everything.
2. Long conversations: older messages may be dropped, so the bot "forgets".
3. A new chat: the model starts with nothing but the system prompt.

## Temperature and seed: why answers change

When the model picks each token it doesn't always take the single most likely one. **Temperature** controls how varied its choices are:

- **0**: nearly always the most likely token, so replies are very predictable.
- **0.7–1**: more varied, natural-sounding replies (the usual setting for chatbots).
- **Above 1**: increasingly random.

A **seed** fixes the random choices. The same model, conversation, temperature and seed give the same reply, which is how you make a bug reproducible.

> **Note:** Different *wording* between runs is normal. Different *facts, decisions or refusals* for the same question is a bug worth reporting.

## What this means for testers

- Test against the system prompt: it's the spec.
- Run important questions several times (the **Run ×5** button in Chat).
- Record the model, settings and the full conversation in every bug report.
- Expect confident mistakes, and check facts yourself.
