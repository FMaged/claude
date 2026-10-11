---
name: sql-writing
description: Use when writing or changing SQL — a query, a join, an aggregate, an upsert, a bulk UPDATE or DELETE, a CTE, or a query embedded in application code (e.g. "write a query that…", "why does this return duplicates", "make this one query", "add an upsert", "make this faster"). Postgres by default; other dialects are flagged where they differ.
---

# Writing SQL

Write the query so a reader can tell what it returns without running it, and so it still
returns the right rows when a column is NULL and when a join matches twice.

For DDL — `CREATE TABLE`, `ALTER`, indexes, grants, triggers, migrations — use the
project's migration review skill instead if it has one.

## 1. Say what you mean

- Name the columns. No `SELECT *` in anything that ships (a view, an application query, a
  migration): it breaks the day a column is added and hides what the query actually depends
  on. Fine when poking around in `psql`.
- Explicit `JOIN ... ON`. Never commas in `FROM`.
- `LEFT JOIN` only when you want the unmatched rows. If every row matches, it is an inner
  join that lies to the reader about the data.
- Alias every table with a short, meaningful name (`price_bar b`), not `t1`, and qualify
  every column once more than one table is in play.
- One clause per line. Keywords uppercase, identifiers lowercase, `AND` and `ON` indented
  under the join they belong to.

## 2. NULL does not behave

The single biggest source of SQL that is wrong rather than slow.

- `NOT IN (subquery)` returns **no rows at all** if the subquery yields one NULL. Use
  `NOT EXISTS`.
- `= NULL` and `<> NULL` are never true. Use `IS NULL`, or `IS DISTINCT FROM` when either
  side may be NULL.
- `count(col)` skips NULLs; `count(*)` does not.
- `sum()` over zero rows is NULL, not 0. `coalesce(sum(x), 0)`.
- Arithmetic and `||` with NULL give NULL, so one missing value empties the whole column.
- A plain `UNIQUE` constraint allows many NULLs. If NULL must collide, use a partial unique
  index over a sentinel, or make the column `NOT NULL`.
- Sorting puts NULLs last in Postgres by default, first in MySQL. Say `NULLS LAST`.

## 3. The join that quietly changes the result

- A condition on the right-hand table in `WHERE` turns a `LEFT JOIN` into an inner join. It
  belongs in `ON`. The exception is `WHERE r.id IS NULL`, which is the anti-join idiom.
- A join through a one-to-many fans rows out and doubles every `sum` and `count` above it.
  Aggregate the many side first — a grouped subquery or a `LATERAL` — then join to it.
- `DISTINCT` is almost always a bandage over a fan-out. Find the join that duplicates rows
  instead of hiding it.
- `GROUP BY` lists every selected column that is not an aggregate. MySQL will let you
  select an ungrouped column and silently pick a row at random; Postgres refuses.

## 4. Make the answer deterministic

- `LIMIT` without `ORDER BY` returns arbitrary rows. "The latest" needs an `ORDER BY` whose
  columns break every tie — add the key as the last sort term.
- Paging with `OFFSET` over a non-unique sort repeats and skips rows between pages, and a
  deep `OFFSET` reads and throws away everything before it. Page by key instead:
  `WHERE (day, id) < ($1, $2) ORDER BY day DESC, id DESC LIMIT $3`.
- `BETWEEN` on a timestamp includes the upper bound, so the last millisecond of the day lands
  in two buckets. Use a half-open range: `ts >= $1 AND ts < $2`.

## 5. Write it so the index can be used

- No function or cast on the indexed column. `WHERE date_trunc('day', ts) = $1` cannot use an
  index on `ts`; a half-open range can. Same for `lower(email) = $1` unless there is an
  expression index to match it.
- An implicit cast across types (a `text` column compared against a number) disables the
  index as surely as a function does.
- `LIKE '%foo'` with a leading wildcard cannot use a btree index. A trigram index can.
- `OR` across two different columns often uses neither index; `UNION ALL` of two indexed
  queries does.
- The leading column of a composite index has to be the one you filter on. An index on
  `(a, b)` does nothing for a query filtering only `b`.
- Filter before joining, and filter the big table first.

## 6. Writes

- Every `UPDATE` and `DELETE` has a `WHERE`. Run the same `WHERE` as a `SELECT count(*)`
  first and look at the number.
- Multi-statement writes go in one transaction. Try it with `ROLLBACK` in place of `COMMIT`
  before you mean it.
- Make the write idempotent rather than careful: `INSERT ... ON CONFLICT (<natural key>) DO
  NOTHING` or `DO UPDATE`. `SELECT` then `INSERT` is a race, whatever the application does
  between the two.
- `ON CONFLICT DO UPDATE` with a `WHERE` when the value may only move forward, so a replay
  with stale data cannot overwrite newer data:
  `DO UPDATE SET v = excluded.v WHERE excluded.as_of > t.as_of`.
- `RETURNING` instead of a second round trip to read back what you just wrote.
- Never read-modify-write a counter in application code. `SET n = n + 1`.
- A bulk `UPDATE` or `DELETE` goes in batches with a commit each
  (`WHERE id IN (SELECT id FROM … ORDER BY id LIMIT 10000)`), so it does not hold locks,
  bloat WAL, or block replication for minutes.
- Writers touching the same rows must take them in the same order, or they deadlock. If you
  lock explicitly, `SELECT ... FOR UPDATE ... ORDER BY id`.

## 7. Parameters, always

- Bind every value. Never build SQL by string formatting or interpolation — not for an
  internal tool, not for a number, not "because it comes from an enum".
- A table or column name cannot be bound. Validate it against a fixed allowlist in code and
  quote it; never pass it through.
- For a list, pass one array parameter (`= ANY($1)`) rather than generating N placeholders,
  which defeats statement caching.
- `LIKE` on user input needs `%` and `_` escaped, or the user chooses the search pattern.

## 8. Types

- Money is integer minor units or `numeric`. Never `float`, `real`, or `double precision`.
- Timestamps are `timestamptz` in UTC. A calendar date in a local zone needs that zone
  spelled out: `(ts AT TIME ZONE 'America/New_York')::date`.
- Integer division truncates. Cast before dividing for a ratio.
- Comparing `numeric` to a float literal reintroduces the rounding you avoided.

## 9. Shape

- Use CTEs to name steps, one idea per CTE. Two joins often read better than six chained
  CTEs. In Postgres 12 and later a CTE may be inlined; before 12 it is always an optimization
  fence, and `MATERIALIZED` / `NOT MATERIALIZED` makes the choice explicit.
- `DISTINCT ON (key) ... ORDER BY key, ts DESC` is the short way to get the latest row per
  group in Postgres; a window function (`row_number() OVER (PARTITION BY …)`) is the portable
  way. Either beats a self-join.
- Do the work in one set-based statement rather than a loop in application code issuing a
  query per row.
- Comment only the non-obvious why — a magic threshold, an ordering that matters, an index
  the query is written around. Follow the `code-comments` skill.

## Before calling it done

```
EXPLAIN (ANALYZE, BUFFERS) <the query>     -- estimated vs actual rows, seq scans, bad nested loops
BEGIN; <the write>; -- check counts -- ROLLBACK;
SELECT count(*) FROM … WHERE <the same WHERE>;   -- before any UPDATE or DELETE
```

A plan where the estimate and the actual row count differ by orders of magnitude means the
planner is guessing — usually a stale `ANALYZE` or a predicate it cannot see through.
