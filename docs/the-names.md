# The names

Every name the Brigade uses, in one table. Skills describe roles; they read the names from
here and from the plugin contract. Renaming stays a one-line change.

## Contents

- [The Brigade (default)](#the-brigade-default)
- [Why a kitchen](#why-a-kitchen)
- [Qafila (alternate)](#qafila-alternate)

## The Brigade (default)

| Kitchen | Plain meaning | In the harness |
|---|---|---|
| **The Brigade** | the whole kitchen team | lead + workers + human, on one machine |
| **Head Chef** | owns the menu, has the final say | the human: signs off plans, merges, deploys |
| **Sous Chef** | runs the line, stands at the pass | the lead session, `/brigade:sous-chef` |
| **Line Cook** | owns one station, one order at a time | a worker session, `/brigade:line-cook` |
| **Station** | a cook's own bench | one gitignored clone, `stations/station-N` |
| **The Walk-in** | the one shared fridge | shared local resources: a database, a docker stack, a port |
| **The Rail** | where fired tickets hang | the ticket store: markdown in `docs/`, GitHub Projects, or Jira |
| **Ticket** | one order | one unit of work |
| **Mise en place** | prep before cooking | the plan |
| **Chef's sign-off** | the head chef approves the dish | plan approval, which authorises the commits made under it |
| **The Pass** | where every plate is checked | the sous's pre-commit review |
| **Health Inspector** | looks, reports, never cooks | the `inspector` sub-agent |
| **"Heard!"** | the line's call and response | `SendMessage` |
| **86'd** | "we're out" | `blocked` |
| **End of shift** | the cook goes home | `/clear`: one ticket per session |

| Lane | Kitchen name | Source |
|---|---|---|
| A | **Specials** | a spec, sliced into tickets |
| B | **À la carte** | standalone tickets already on the rail |
| C | **Clean as you go** | the kitchen generates them: `/brigade:clean scan` |

## Why a kitchen

Escoffier's *brigade de cuisine* (1890s) is a hierarchy built so a kitchen can scale
without chaos: every station has one owner, orders are tickets, and one gate, the pass,
stands between the kitchen and the customer. That is exactly the problem of running several
coding agents at once in one shared space. And "clean as you go" is a real kitchen rule:
you don't wait for closing time, or service grinds to a halt.

## Qafila (alternate)

The same roles as a caravan, for Urdu-speaking rooms.

| Role | Brigade | Qafila |
|---|---|---|
| Human | Head Chef | Saudagar (سوداگر, the merchant) |
| Lead | Sous Chef | Salar (سالار, caravan leader) |
| Worker | Line Cook | Sarban (ساربان, camel driver) |
| Clone | Station | Hujra (حجرہ, a cell in the caravanserai) |
| Machine | The Kitchen | Sarai (سرائے, caravanserai) |
| Shared resource | The Walk-in | Kuan (کنواں, the well) |
| Ticket store | The Rail | Bahi (بہی, the ledger) |
| Approved plan | Chef's sign-off | Parwana (پروانہ, a permit) |
| Pre-commit review | The Pass | Chungi (چنگی, customs post) |
| Report-only reviewer | Health Inspector | Chowkidar (چوکیدار, watchman) |
| Message | "Heard!" | Paigham (پیغام) |
| Lanes A / B / C | Specials / À la carte / Clean as you go | Naya Maal / Bazaar / Naalband |
