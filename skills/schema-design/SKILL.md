---
name: schema-design
description: Use when designing a database schema or modelling new data, before any DDL exists (e.g. "what tables do I need for this", "model this domain", "design the schema", "where does this new entity go", "should this be one table or two", "natural key or an id here"). Interviews, then records the grain, keys, and types of each table and why. For DDL that is already written as a migration, use sql-review instead.
---

# Schema Design

Decide what a row *is* before deciding what columns it has. Most schema pain is a table whose
grain was never stated, so rows at two different grains ended up in it.

This skill stops at the design. Writing the migration that creates it is the migration skill's
job; the queries that read it are `sql-writing`.

## 1. Before any table

Answer these out loud, with the user, and write the answers down:

- **What facts arrive from outside, and what is derived from them.** Derived values are never
  accepted as input — a caller that can send you a computed field can send you a wrong one.
  Decide for each derived value: a generated column, a `BEFORE INSERT` trigger that overwrites
  it, or a view. A trigger beats a `CHECK`: a check refuses a bad write, a trigger makes one
  impossible.
- **What must never be rewritten.** Decide this per table, now, and enforce it with grants
  rather than with convention — the application role simply has no `UPDATE`. A promise that
  history is never edited is worth less than a database that cannot edit it.
- **Which table grows without limit.** Usually one or two. Everything about indexes,
  partitioning and retention follows from that answer.
- **What makes two rows the same thing.** That is the natural key, and it is also the
  idempotency key for every job that writes the table.

## 2. State the grain

For every table, one sentence: "one row per ___". If the sentence needs an "and" plus a
"sometimes", it is two tables.

The grain tells you the primary key immediately — the key is exactly the columns in that
sentence. `one row per (instrument, trading day)` is `PRIMARY KEY (instrument_id, day)`,
and the question of whether to add a surrogate id answers itself.

Put the grain sentence in the schema doc next to the table. It is the thing a reader needs
most and the thing nobody writes down.

## 3. Keys

- **Natural key first.** If the columns that identify the row already exist, make them the
  primary key. A surrogate id on top of a natural key is one more column and one more way to
  insert the same fact twice.
- **A surrogate id earns its place** when the natural key is wide and referenced from many
  tables, when it is text supplied by a third party, or when the identity itself may change.
  When you add one, keep the natural key as a `UNIQUE` constraint — it is what makes the
  writer idempotent.
- `bigint` identity (`GENERATED ALWAYS AS IDENTITY`) over `serial`. UUIDv4 only when ids must
  be generated outside the database or must not be guessable; it costs index locality, so use
  UUIDv7 if you have it.
- **A unique constraint is a design statement, not a safety net.** Every "this cannot happen
  twice" rule in the requirements is a unique index, or it is a rule that will be broken.
- Order the unique index's columns so it also serves the main lookup, and you need one index
  instead of two.

## 4. One table or two

- Normalize first. Denormalize only with a named query, a measured problem, and a note saying
  which copy is authoritative.
- A nullable group of columns that are always all set or all null is a separate table with a
  one-to-one relationship.
- A column that means something different depending on another column's value is two columns,
  or two tables.
- Repeating columns (`phone1`, `phone2`) are a child table.
- A status that has its own timestamps, actor and reason is an event table, not a column. If
  you need the history of a value, the value is a row somewhere.
- Resist a single polymorphic "owner_type/owner_id" pair: it cannot have a foreign key. Either
  one child table per parent, or a nullable FK per parent with a `CHECK` that exactly one is
  set.

## 5. Types

- Money is `bigint` in minor units, or `numeric` with explicit precision. Never a float.
  Decide the unit once and name it in the column (`amount_cents`), or the second reader
  guesses.
- Quantities that cannot be fractional are integers.
- `timestamptz`, stored UTC, always. `timestamp` without time zone is a bug waiting for a
  deploy to another machine. A local calendar date needs its zone named at the point of
  conversion.
- `text`, not `varchar(n)` with an arbitrary `n`. Add a `CHECK` when there is a real limit.
- An enum is `text` with a `CHECK`, not a Postgres `enum` type — extending a check is a
  one-line migration, extending an enum type is awkward and cannot be done inside a
  transaction in older versions.
- `NOT NULL` is the default; a nullable column has to justify itself, because every query
  that touches it now has three outcomes instead of two. Never use a sentinel
  (`''`, `0`, `9999-12-31`) in place of NULL.
- `jsonb` for a payload you store and return whole — a third party's raw response, an audit
  blob. Not for fields you filter, join or aggregate on. If you are writing
  `WHERE data->>'x' = …` in anger, it was a column.

## 6. Relationships

- Every foreign key is declared, with an explicit `ON DELETE`. Choose per relation:
  `RESTRICT` for anything you would rather fail than lose, `CASCADE` only where the child has
  no meaning without the parent.
- Index every foreign key you delete or join through.
- A many-to-many join table takes the pair as its primary key, plus whatever is true about the
  pairing.
- Prefer deleting nothing. A record that must disappear from the product can have a state, and
  a view that hides it, which keeps the history intact.

## 7. Time

- Separate **when it happened** from **when you learned it** (`occurred_at` vs `recorded_at`,
  or `as_of` vs `created_at`). Any system that revises its own past data needs both, and
  bolting the second one on later is a rewrite.
- A value that is true for a period is a row with a half-open range (`valid_from`,
  `valid_to NULL` for current). `daterange` plus an exclusion constraint stops overlaps.
- Reference data that tests depend on (a calendar, a tax table, a list of codes) belongs in a
  migration, not a test fixture — a test cannot rely on something that shifts at run time.

## 8. Names

- Follow whatever the project already does. Otherwise: `snake_case`, singular table names
  (`price_bar`, not `price_bars`), `<table>_id` for a foreign key, no type or `tbl_` prefixes.
- Avoid reserved words — `user`, `order`, `group`, `end`. Rename rather than quote forever
  (`app_user`, `paper_order`), and write down why the name differs from the domain term.
- The same concept keeps the same column name in every table it appears in.

## Interview

Use `AskUserQuestion`, a few at a time, recommended (simplest) option first with one line on
why. Ask about:

1. **The facts** — what arrives from outside, how often, from whom, and what is derived.
2. **The grain** — one sentence per table, confirmed with the user in their words.
3. **Identity** — what makes two rows the same fact; whether that key is stable.
4. **Mutability** — per table: append-only, or what is allowed to change and who may change it.
5. **Volume and retention** — what grows forever, what can be dropped, how far back queries go.
6. **The three or four queries that matter** — the schema exists to answer them, and they
   decide the indexes.

Skip what does not apply. If the user says "you decide", take the simplest option and record
it as a decision.

Show the entity list and each table's grain sentence, and get agreement, before writing
anything down.

## What to write down

Put it where the project already keeps its schema notes. If `DESIGN.md` exists (zero-to-prod
chain), write into its `## Database` section first. Otherwise use `doc/database.md`,
`doc/entities.md`, or a `## Schema` section of `PLAN.md`. Only create a new file if there is nowhere obvious.

Record, per table: the grain sentence, the primary key and why it is that key, the columns
with their types and nullability, the foreign keys with their `ON DELETE`, the unique
constraints and the rule each one enforces, and the indexes with the query behind each.

Record the decisions separately, with the alternative that was rejected:

```markdown
### D<n>: <the decision>
- **Choice:** <what>
- **Why:** <reason>
- **Rejected:** <the other option, and what it would have cost>
```

A mermaid `erDiagram` of the relationships pays for itself the moment there are more than
about eight tables.

Then hand off: the schema becomes a migration, and the migration gets reviewed by
`sql-review` before it runs anywhere. Say that in one line and offer to write it.
