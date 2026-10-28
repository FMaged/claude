---
name: sql-review
description: Use when reviewing SQL — a query, a view, a stored function, a bulk write, a query in application code or an ORM-generated statement (e.g. "review this query", "check this SQL", "why is this slow", "is this UPDATE safe to run", "does this return the right rows"). Reports what returns the wrong rows, what is unsafe to run, what blocks other writers, and what cannot use an index, with the file and line.
---

# SQL Review

Review queries, views, functions, and the SQL embedded in application code. Report problems.
Do not rewrite unless the user asks.

For DDL — schema changes, indexes, grants, triggers, migrations — use the project's
migration review skill if it has one. Rules for writing new SQL are in the `sql-writing`
skill; this skill is the reading pass.

## 1. Does it return the right rows

Say this first. A slow query is an annoyance; a wrong one is a wrong number on a screen that
nobody questions.

- **`NOT IN (subquery)`** where the subquery column is nullable. One NULL and the query
  returns nothing. `NOT EXISTS`.
- **A `LEFT JOIN` filtered in `WHERE`.** A predicate on the right-hand table in `WHERE`
  silently makes it an inner join. Only `IS NULL` belongs there, as an anti-join.
- **Fan-out.** Any aggregate above a join through a one-to-many is multiplied. Follow each
  `sum`, `count` and `avg` down to the grain of its rows and say what the real multiplier is.
- **`DISTINCT` or `GROUP BY` covering a fan-out** rather than fixing it — the counts are
  still wrong even when the row list looks right.
- **`count(col)` where `count(*)` was meant**, and `sum()` over an empty set returning NULL
  into something that expects 0.
- **`= NULL`, `<> NULL`,** or a `NOT (a = b)` that was meant to catch NULLs.
- **`BETWEEN` on a timestamp**, which includes the upper bound and double-counts the boundary.
- **Timezone.** A date derived from a `timestamptz` without naming a zone, or a `timestamp`
  without time zone used as though it were absolute.
- **Money in a float.** Any arithmetic on `real` or `double precision`, or a `numeric`
  compared against a float literal.
- **`LIMIT` without a total `ORDER BY`**, including the case where the sort has ties and the
  query claims to return "the latest".
- **`OFFSET` pagination** over a non-unique sort: rows repeat and rows are skipped between
  pages.
- **`UNION` where `UNION ALL` was meant**, or the reverse — one silently dedupes and sorts,
  the other silently keeps duplicates.

## 2. Is it safe to run

- An `UPDATE` or `DELETE` with no `WHERE`, or a `WHERE` on a column that is not the key it
  looks like.
- A bulk write in one statement: how many rows, how long the lock is held, how much WAL it
  writes, and whether a replica or a nightly job is behind it. Say whether it should be
  batched.
- Several statements that must all apply, with no transaction around them.
- `TRUNCATE` or a `DELETE` with no recovery path and no copy taken first.
- A write that is not idempotent where it may be retried — `SELECT` then `INSERT`, or an
  `INSERT` without `ON CONFLICT` on a natural key. Name the duplicate it creates on replay.
- `ON CONFLICT DO UPDATE` with no guard, so a replay with stale data overwrites newer data.
- A query run against production to "check something" that takes a lock — `SELECT ... FOR
  UPDATE`, `LOCK TABLE`, or a DDL statement hiding at the end of the file.

## 3. Injection and permissions

- Any SQL assembled by string formatting, interpolation, or concatenation. Report it as a
  blocker even when the input "cannot" be hostile, and even for a number — it is also how
  queries break on an apostrophe.
- An identifier (table, column, sort direction) taken from input without an allowlist. This
  is the one a parameter cannot fix.
- `LIKE` on user input with `%` and `_` unescaped.
- A dynamic query inside a stored function without `format(%I, %L)` or the equivalent.
- `SECURITY DEFINER` with a mutable `search_path`.
- A query that reads columns the caller has no business seeing, or writes through a role that
  should be read-only.

## 4. Will it use an index

Read the plan, do not guess. Then check the usual causes:

- A function or cast wrapping the filtered column, with no matching expression index.
- An implicit cast because the parameter type does not match the column type.
- `LIKE '%…'`, or a regex, on a btree-indexed column.
- `OR` across two columns where neither index can serve the whole predicate.
- A composite index whose leading column is not the one filtered.
- A correlated subquery in `SELECT` executed per output row where a join would run once.
- `ORDER BY` that cannot be satisfied by an index, over a result set big enough that the sort
  spills to disk.
- A query issued once per row by the application — the N+1 — visible as a query inside a loop
  or inside a per-item function.

Then look at the plan itself: actual rows far from the estimate, a sequential scan on a large
table, a nested loop whose outer side is large, a hash join spilling to disk, or `Rows
Removed by Filter` far larger than the rows returned.

## 5. Concurrency

- Two write paths taking the same rows in different orders — a deadlock waiting for load.
- A read-modify-write on a counter or a balance instead of `SET n = n + 1`, or without
  `FOR UPDATE`.
- A transaction held open across a network call, a model call, or user think-time.
- A long-running read on the primary that blocks a migration behind it, and so blocks
  everything behind that.
- An advisory lock taken and not released on every path out.

## 6. Clarity and maintenance

Lower priority. Do not pad a review with these when something above is wrong.

- `SELECT *` in a view, an application query, or a migration.
- Unqualified columns in a multi-table query, or aliases like `t1`, `a`, `x`.
- A magic literal that should be a parameter or a named constant — an id, a status string, a
  threshold.
- Dead weight: a join to a table nothing selects from, a CTE nothing references, a `GROUP BY`
  on an already-unique key, a redundant `DISTINCT`.
- Six chained CTEs where two joins would read better, or a self-join where `DISTINCT ON` or a
  window function says it in one line.
- Duplicated query logic that has drifted between two call sites.

## Commands

```
EXPLAIN (ANALYZE, BUFFERS) <query>          -- never review a performance claim without this
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) <query>   -- on a copy, if ANALYZE would run a write

BEGIN; <the write>; SELECT count(*) FROM …; ROLLBACK;   -- what it would actually touch

SELECT count(*) FROM … WHERE <the WHERE from the UPDATE>;   -- blast radius, before approving

-- is the index the query needs actually there, and used
SELECT indexrelname, idx_scan FROM pg_stat_user_indexes WHERE relname = '<table>';
\d+ <table>
```

`EXPLAIN` without `ANALYZE` gives estimates only; `ANALYZE` runs the statement, so for a
write it goes inside a transaction that rolls back.

## How to report

Most serious first, as a list:

```
<file>:<line> — <blocker | should fix | nit>: <what is wrong and which rows or which writes it gets wrong>
Fix: <the change, one line>
```

For a correctness finding, say concretely what the query returns today and what it should
return — "this double-counts every account with more than one open position" is a review;
"possible fan-out" is a shrug. For a performance finding, quote the plan line that proves it.

Separate the findings that return wrong data from the ones that are merely slow or untidy.
The reader needs to know which kind they are looking at before they merge.

If the query is fine, say so in one sentence and name the two or three things you checked
hardest — usually the NULL cases, the join grain, and the plan. Do not invent findings to
fill a list. If you add a comment as part of a fix, follow the `code-comments` skill.
