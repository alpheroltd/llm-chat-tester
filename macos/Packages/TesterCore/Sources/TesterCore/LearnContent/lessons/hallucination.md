> **Draft:** Sample lesson written to show the format. Your team's material will replace it.

A **hallucination** is when a chatbot states something false as if it were true: a made-up fact, source, price or policy. It's the most common chatbot bug, and often the most expensive.

## Why it happens

An LLM writes the most *plausible* next words. When it has the facts (in its system prompt or training), plausible and true usually match. When it doesn't, the most plausible continuation is often a confident invention.

- It rarely says "I don't know" unless it has been told to.
- It sounds just as sure when it's wrong as when it's right.
- The more specific the question, the more specific the invention.

## Where to look

1. **Facts from the spec:** prices, opening hours, policies, product features. Check every one against the system prompt.
2. **Things that don't exist:** a product model number, a book, an event. A good bot says it can't find it.
3. **Sources and links:** ask where it got the information. Invented URLs and citations are common.
4. **False premises:** state something wrong in your question and see whether the bot corrects it or agrees.

> **Tip:** Keep a short list of "trap" questions for each client bot: a few facts from the spec, one thing that doesn't exist, and one false premise. Re-run them after every change.

## Grounding

Teams reduce hallucination by **grounding** the bot: giving it trusted information to answer from, such as the client's policy documents, and telling it to stay within them. Grounding doesn't remove the need to test. It changes the question to "does the bot stick to what it was given?"

## Why clients care

Customers act on what a bot tells them. Companies have been held responsible for refunds and policies their chatbots made up, so a hallucinated policy is a business risk, not just a wrong answer.

> **Note:** When you report a hallucination, include the correct fact and where it comes from (the spec or system prompt), so the developer can see the gap.

## What this means for testers

- Check every fact against the spec. Don't trust confident wording.
- Test unknowns and false premises, not just normal questions.
- Re-run facts several times: a bot can be right once and wrong the next time.
