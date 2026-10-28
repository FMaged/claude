---
name: svelte-review
description: Use when reviewing Svelte or SvelteKit code — a component, a page or layout, a load function, a form action, a remote function, a hook, a .svelte.ts store, or a whole frontend diff (e.g. "review this component", "check my +page.server.ts", "why does this not update", "is this load function right", "look over the frontend"). Reports what leaks to the browser, what runs as raw HTML, what stops updating, what leaks memory, and what breaks on SSR or under a newer SvelteKit, with the file and line.
---

# Svelte review

Review Svelte 5 and SvelteKit code. Report problems. Do not rewrite unless asked.

How the code should be written is in the `svelte` skill; this one is the reading pass. For a
full security audit of the backend use `web-security-review`; for SQL, `sql-review`. If the
project has its own invariants skill, check it as well — its rules win.

## 0. Map it first

Before reading any one component, write down:

- **Versions and mode**: `svelte`, `@sveltejs/kit`, the adapter (from `package.json` and the
  lockfile). Runes forced on (`compilerOptions.runes`), or legacy files still present.
  Whether `experimental.async` or `experimental.remoteFunctions` is on. Several findings
  below depend on these.
- **Where code runs**: SSR on or off (`export const ssr`), prerendered or not, SPA with a
  `fallback`. With `adapter-static`, no server code runs after the build.
- **Every way data comes in**: universal and server `load`s, `+server.ts` endpoints, form
  actions, remote functions (`*.remote.ts`), `fetch` calls in components and effects.
- **Every way data goes out to the page**: what each server `load` returns, what
  `{@html}` renders, what `href`/`src` attributes are built from.
- **Where the user is checked**: `hooks.server.ts` `handle`, a layout's server `load`, each
  action and endpoint.

Then review the riskiest paths first: §1 before §2, and so on.

## 1. What reaches the browser that should not

- **`{@html}` with anything not written by the developer** — API data, user input, model
  output, Markdown rendered without a sanitiser, a sanitised string changed afterwards.
  Every `{@html}` is a finding unless its input is a constant or passes through DOMPurify
  (or similar) immediately before rendering.
- **URLs from data in `href`, `src`, `action`, `formaction`, or `goto()`** without a scheme
  check. `javascript:` runs script; Svelte escapes text, not URLs.
- **A server `load` returning the whole row or object.** Everything it returns is
  serialised into the page HTML and readable by anyone who can load the page: hashes,
  tokens, internal flags, other users' fields.
- **Secrets in the bundle**: a key read through `import.meta.env.VITE_*`, `$env/static/public`,
  `PUBLIC_*`, or a Kit 3 variable with `public: true`; a server-only module that is not
  named `*.server.*` and not under a `server/` directory (Kit 2: `src/lib/server/`), so it
  can be imported into the browser. Check `build/` or `.svelte-kit/output/client` for the
  value if a build exists.
- **Per-user data in module-level state on an SSR server** — a `let` or `$state` at the top
  of a `.svelte.ts`, a `<script module>`, or a server file, written during a request. The
  next request, from another user, sees it.
- **`handleError` returning `error.message` or the stack** for unexpected errors.
- **Source maps or `$inspect`/`console.log` of data** left in a production build.

## 2. Who can do what they should not (SvelteKit server)

Skip when nothing runs on a server (adapter-static, no prerendered actions).

- **Authorisation only in `+layout.server.ts`.** It does not run for form actions,
  `+server.ts` endpoints, or remote functions, and it does not rerun on every client
  navigation. Each of those must check `locals.user` itself, or `handle` must guard the
  path.
- **A remote function with no validation** (`'unchecked'` on input that is not truly free)
  or no authorisation inside it. Each `query`, `form`, and `command` is a public endpoint.
- **An object loaded by id from `params` with no ownership check.**
- **Server-owned values taken from the form**: a price, a user id, a role, a "paid" flag.
- `redirect()` to a URL from `url.searchParams` without checking it is a path on this site,
  or with `{ external: true }` on user input.
- `csrf.trustedOrigins: ['*']` (Kit 3) or `csrf.checkOrigin: false` (Kit 2) with no reason
  written next to it.
- Cookies set without `httpOnly`, `secure`, `sameSite`, or `path`.

Hand anything deeper to `web-security-review`.

## 3. What stops updating (reactivity)

The most common Svelte 5 bug: code that runs once and is then silently stale.

- **Destructuring state or a reactive object**: `let { name } = user` where `user` is
  `$state`, or `const { x } = page.url` at the top of a script. Fine on `$derived`.
- **A value passed where a reactive reference was needed**: `useThing(count)`,
  `setContext('k', count)` with a primitive, `new Chart(data)` that never sees updates.
- **State initialised from a prop or `data` once** — `let rows = $state(data.rows)` — then
  the user navigates to the same route with different params, the component is reused, and
  `rows` is stale. Should be `$derived`, or the copy is deliberate and named so.
- **Mutating `$state.raw`** (or a fallback prop value, which is not a proxy) and expecting
  an update.
- **Mutating a `Map`, `Set`, `Date`, or `URL` in `$state`** instead of using `SvelteMap`,
  `SvelteSet`, `SvelteDate`, `SvelteURL`, or reassigning.
- **Dependencies read after `await`** or inside a callback in an `$effect` or `$derived` —
  they are not tracked.
- **Runes in a plain `.ts`/`.js` file** (must be `.svelte.ts`), or a module exporting a
  reassigned `$state` primitive.
- **A class method passed as a handler** (`onclick={store.reset}`) that uses `this`.
- **Legacy reactivity in a runes file or project**: `$:`, `export let`, `$store` on a
  value that is no longer a store, `$page` from the removed `$app/stores` in Kit 3.

## 4. Effects that do the wrong job

- **`$effect` that writes state derived from other state** — should be `$derived`. Look
  for an effect whose body is one assignment.
- **`$effect` reacting to a user action** by watching the state the handler set — the work
  belongs in the handler. Symptom: a flag that is set, then reset inside an effect.
- **An effect that reads and writes the same state** — loops or hits
  `effect_update_depth_exceeded`.
- **Fetch in an effect with no abort** — a slower older response overwrites a newer one.
  Needs `AbortController` in the cleanup or `getAbortSignal()`; in SvelteKit usually a
  `load`.
- **No cleanup returned** for an interval, listener, observer, socket, subscription, or
  library instance (`chart.dispose()`, `map.remove()`). A memory leak that grows with every
  navigation; confirm by navigating away and back in the dev tools memory panel.
- `$effect.root` whose cleanup is never called.
- `untrack` used to silence a loop that should have been fixed.

## 5. What breaks on SSR or hydration

Skip the SSR items when `ssr = false` everywhere; hydration items still apply to
prerendered pages.

- `window`, `document`, `localStorage`, `matchMedia`, or a browser-only library touched at
  the top of a component script, in a universal `load`, or in a module imported by one.
  Needs `browser`, `onMount`, `$effect`, or a dynamic import.
- **Global `fetch` with a relative URL in a `load`** instead of the `fetch` argument: fails
  on the server, skips cookie forwarding, and fetches twice on hydration.
- **Values that differ between server and client**: `Date.now()`, `Math.random()`, ids not
  from `$props.id()`, `toLocaleString()` without a fixed locale and `timeZone`.
- `bind:this` element used before mount.
- An un-awaited promise returned from a server `load` with no `.catch` and no `{:catch}`.

## 6. SvelteKit data flow

- **Waterfalls**: sequential `await`s on independent requests; `await parent()` before the
  load's own requests; a layout and a page both fetching the same thing.
- **`try/catch` around `error()` or `redirect()`** that swallows them. Must rethrow when
  `isHttpError(e) || isRedirect(e)`.
- **`throw fail(...)`** in an action — an error; `fail` is returned. And an action that
  returns the submitted password or other secrets in its `fail()` data.
- **Server-only features with `adapter-static`**: a `+page.server.ts` load, an action, or a
  `+server.ts` that will not exist after the build.
- **Load that never reruns** when it should: data keyed by something not read through
  `params`/`url`, with no `depends()` and no `invalidate()`. Or the opposite: a load that
  reads `url.searchParams` it does not need and reruns on every filter change.
- **Client data fetched in `onMount`/`$effect` where a `load` fits** — loading flicker, no
  SSR, no preloading, races.
- Form posts with `use:enhance` and a custom callback that never calls `update()`.
- Navigation with `window.location` or `history.pushState` inside the app instead of
  `goto` or `<a>`.

## 7. Templates

- **`{#each}` without a key** over a list that is reordered, filtered, inserted into, or
  whose items hold inputs, component state, or transitions. **Index as the key** is the
  same bug. A key that can repeat throws `each_key_duplicate` at runtime.
- `{#await}` with no `{:catch}`.
- Click handlers on non-interactive elements (`<div onclick>`), links without `href`, a
  `<button>` inside a `<form>` without `type="button"` that submits it by accident.
- `{@debug}` or `$inspect` left in.

## 8. Deprecated or removed APIs

Check against the installed versions; each is a build error or a migration debt.

- **Kit 3 removed**: `$app/stores`, `$lib` (unless re-aliased), `$service-worker`,
  `svelte.config.js`, the `kit:` config namespace, `csrf.checkOrigin`,
  `goto({ noScroll, keepFocus })`, `data-sveltekit-noscroll`/`keepfocus`.
- **Kit 3 deprecated**: `$app/environment`, `$env/*` modules, `invalidateAll`,
  `goto({ invalidateAll, replaceState })`, `update({ invalidateAll })`, `pushState`,
  `replaceState`, `export const snapshot`, `error(status, { message })`, `asset('/x')` with
  a leading slash.
- **Svelte 5 deprecated**: `createEventDispatcher`, `on:` directives, `<slot>`,
  `beforeUpdate`/`afterUpdate`, `$$props`/`$$restProps`, `<svelte:component>` (components
  are dynamic by default), `spring`/`tweened` stores, `new Component(...)`.
- Legacy and runes syntax mixed in one file, or `run()` from `svelte/legacy` left by the
  migration tool.

## 9. Types

- Components without a typed `Props` interface, or with `any` props.
- `data` typed by hand instead of `PageProps` / `PageData` from `./$types`.
- `as SomeType` on API responses with no check — the type promises a shape nobody verified.
  A hand-written API type must have one home and a pointer to the contract it mirrors.
- `// @ts-ignore` or `// @ts-expect-error` without a reason.
- `svelte-check` errors or warnings ignored in CI, or `tsc` run in its place (it does not
  read `.svelte` files).

## 10. Accessibility

- Compiler `a11y_*` warnings silenced with `<!-- svelte-ignore -->` and no reason.
- Inputs without labels; icon-only buttons without `aria-label`; charts without a text
  alternative.
- Pages without `<svelte:head><title>`.
- Animations that ignore `prefersReducedMotion`.
- Focus not moved to a dialog or an error message that appears after an action.

## 11. Performance

- Deep `$state` around large data that is only replaced (should be `$state.raw`).
- A heavy library (charts, editors, maps, date libraries) imported eagerly in the root
  layout, or imported whole instead of per part.
- A `$derived` over a big list that also reads the search input, recomputing per keystroke
  with no debounce.
- Thousands of rows rendered with no pagination or virtualisation.
- `$effect` that rebuilds a chart or widget from scratch on each update instead of updating
  it.

## 12. Styles and structure

- Bare `:global(...)` selectors in a component, leaking to every page.
- Unused-selector warnings left in.
- A component that fetches, transforms, and renders — the transformation belongs in a
  tested `.ts` module.
- The same formatting logic (money, dates, percentages) written inline in several
  components instead of one tested function.

## Commands

```
npm ls svelte @sveltejs/kit                                         # which rules apply
npx svelte-check --tsconfig ./tsconfig.json --fail-on-warnings
npx vitest run
npx vite build                                                     # server-only imports, prerender errors

# leads for §1–§8
rg -n '\{@html' src
rg -n 'href=\{|src=\{|goto\(' src                                  # URLs built from data
rg -n 'VITE_|\$env/static/public|\$env/dynamic/public|PUBLIC_|public: true' src
rg -n '\$effect\(' src                                             # each one: is it a $derived? does it clean up?
rg -n 'fetch\(' src --glob '!*.server.*'                           # in effects or load without event.fetch
rg -n '\{#each [^}]*\}' src | rg -v '\('                            # each blocks without a key
rg -n 'export let |^\s*\$:|on:[a-z]+=|createEventDispatcher|<slot|\$app/stores|\$app/environment|invalidateAll' src
rg -n 'svelte-ignore|@ts-ignore|@ts-expect-error' src
rg -n 'window\.|document\.|localStorage' src                       # SSR leads; check each is guarded

# after a build: did a secret reach the client bundle?
rg -n '<the secret value or its variable name>' build .svelte-kit/output/client
```

A grep hit is a lead, not a finding. Read the code around it and say what actually breaks.

## How to report

Most serious first, as a list:

```
<file>:<line> — <blocker | should fix | nit>: <what breaks, for whom, when>, because <cause>
Proof: <the steps, the input, the command output, or the warning that shows it>
Fix: <the change, one line>
```

- **blocker**: a secret or another user's data reaches the browser; `{@html}` or a URL
  sink renders data an attacker can influence; an action, endpoint, or remote function
  any user can call to read or change what they should not; a page that crashes on SSR or
  fails to build with the installed version.
- **should fix**: UI that silently shows stale or wrong data; a race between requests; a
  leak that grows with navigation; an accessibility failure that blocks keyboard or screen
  reader use; a deprecated API that the next major removes.
- **nit**: style, naming, a missing type, a performance cost nobody will notice yet.

Mark each finding confirmed (reproduced, or traced from the source to the symptom) or
unconfirmed (the pattern is there but you could not tell whether it bites). Keep
unconfirmed ones to one line each, naming what to check. Say which commands you ran and
which you only read; if the project keeps written review reports, match their format.

If the code is fine, say so in one sentence and name what you checked hardest — usually
the `{@html}` sinks, what the server loads return, and every `$effect`. Do not invent
findings to fill a list. If you add a comment as part of a fix, follow the `code-comments`
skill.
