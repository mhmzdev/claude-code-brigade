---
type: adr
title: A free cook's [check-in] stays a message to the sous; other check-ins and [status] go to a file
status: accepted
date: 2026-11-03
source: ask A7 (#65 Q3)
supersedes: null
---

# 005 — A free cook's [check-in] stays a message to the sous; other check-ins and [status] go to a file

## Question

#65 sends the sous only `[gate]`, `[plan]`, `[handoff]`, `[walk-in]` and `[served]`. A status file can't wake an idle sous, so how does the sous learn that a cook is free?

## Head chef said

> Keep [check-in] free (Recommended)

## Decision

A cook with no ticket, a clean station and a fresh session sends `[check-in]` as a message, once. Every other check-in, and every `[status]`, goes to the station's status file, which `kitchen.sh board` reads.

## Why

A free cook must never sit unbriefed. One sous turn per free cook is cheap. Reading the board after each clear would miss cooks the head chef opens or clears.

## Applies to

Contract 6's message table and the line-cook skill, as built in #65.
