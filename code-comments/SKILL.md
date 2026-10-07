---
name: code-comments
description: Use whenever writing, changing, or reviewing code comments in any language (e.g. "add comments", "document this function", "are these comments good?"). Also apply while writing any new code. Keeps comments few, small, and only where the code cannot speak for itself.
---

# Code Comments

Comments should be rare. Good code explains itself; a comment is for the bit that cannot.

## When to write one

Only these three cases:

1. **Unreadable code** – the logic is dense or tricky and cannot be made clearer by renaming or splitting it.
2. **A workaround** – the code looks wrong but is deliberate (a bug in a library, a quirk of the API, an edge case). Say what forces it.
3. **A non-obvious why** – a magic number, an ordering that matters, a deliberate omission.

Before writing a comment, try to delete the need for it: a better name, a smaller function, an early return. Prefer that over the comment.

## When not to write one

- Restating the code (`// increment i`, `// loop over users`).
- Explaining something an obvious name already says.
- Headers, banners, dividers, or decoration.
- Noting what you just changed, or who changed it. That belongs in the commit.
- Commented-out code. Delete it.
- A docstring on every function just because it exists. Write one when the signature is not enough.

## Style

- One line where possible. Two at most.
- Plain English, lowercase sentence, no essay.
- Sits directly above the line it explains, or at the end of that line if it is very short.
- Says *why*, not *what*.

## Examples

Good:
```python
# the API returns ids as strings, so sort numerically
ids.sort(key=int)
```
```go
// retry once: the first call after a cold start always times out
```
```js
// 1024 is the smallest size the decoder accepts
const CHUNK = 1024;
```

Bad:
```python
# sort the ids
ids.sort(key=int)
```
```js
// ---------- helpers ----------

/**
 * Gets the user.
 * @param id the id
 */
function getUser(id) { ... }
```

## Reviewing

When asked to review or clean up comments, remove every comment that does not fall into the three cases above, and shorten the ones that stay.
