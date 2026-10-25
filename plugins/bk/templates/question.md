---
type: question
title: <one line: the question>
status: open             # open | answered | dropped
asked: YYYY-MM-DD
blocks: [<ID>]           # tickets waiting on it
source: <ID> Q3          # the journal question it came from, or the ask log's id (A3)
answered: null           # YYYY-MM-DD once the head chef answers
gap: null                # what the kitchen lacked that made this the head chef's question: context | ruling | harness | access
fix: null                # what closed the gap: a path in the record, a ticket id, an issue URL, or "none needed"
---

# <title>

## Question

<The question in full, with the context a reader needs: which ticket, which flow, what
the cook was about to do.>

## Options

1. <option> — <what it means>
2. <option> — <what it means>

**Recommendation:** <the sous's, with one line of why>

## What the record holds

<The commis's result: `nothing recorded in <places>`, or the near misses it found, cited.>

## Head chef said

> <their words, verbatim, once they answer>

## Answer

<The structured version: the decision, why, what it applies to. This section is what the
commis quotes back. If the decision outlives this ticket, it is also written as a decision
in `docs.decisions`, citing this file.>

## The gap

<Why this had to be asked at all, in one or two lines: the record didn't hold it (context),
no rule covered it (ruling), a tool or skill was missing (harness), a credential or CLI was
missing (access). `fix:` above says what closed it, so the next session doesn't ask.>
