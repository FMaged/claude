---
name: svelte
description: Use when writing or changing Svelte or SvelteKit code — a component, runes ($state, $derived, $effect, $props), snippets, a +page or +layout, a load function, a form action, a remote function, a hook, an endpoint, shared state, a test, or the SvelteKit/Vite config (e.g. "add a component", "make this reactive", "why doesn't this update", "add a page", "load data for this route", "move this to runes", "wire up this chart"). Svelte 5 with runes and SvelteKit 3, with what differs in SvelteKit 2 called out. For reviewing Svelte code, use svelte-review instead.
---

# Svelte

Write components where every value is one of three things: **state** (`$state`), **derived
from state** (`$derived`), or **a side effect at the edge** (`$effect`, an event handler, an
attachment). Most Svelte bugs are a value that is the wrong one of the three.

For a security pass use `web-security-review`; for comments, `code-comments`. If the project
has its own invariants skill, it wins over anything here.

## 0. Check the versions before writing a line

Run `npm ls svelte @sveltejs/kit @sveltejs/adapter-static @sveltejs/adapter-node` and read
`vite.config.*` and `svelte.config.*`. Svelte 4 and 5 and SvelteKit 2 and 3 differ enough
that code written for the wrong one fails to build or fails silently. When the API in doubt
is new, the installed types are the truth, not memory:
`node_modules/svelte/types/index.d.ts`, `node_modules/@sveltejs/kit/types/index.d.ts`.

Runes mode is per file in Svelte 5: a file that uses a rune is in runes mode, and legacy
syntax in it (`export let`, `$:`, `on:click`, `<slot>`) is a compile error. Projects often
force it on with `compilerOptions.runes`. Write runes in new code. Do not mix the two styles
in one file; migrate a legacy file whole (`npx sv migrate svelte-5`) and then read the
result, because the migration leaves `run()` from `svelte/legacy` wherever it gave up.

| Old | Now |
|---|---|
| `export let x` | `let { x } = $props()` |
| `$: y = x * 2` | `let y = $derived(x * 2)` |
| `$: { sideEffect(x) }` | `$effect(() => { sideEffect(x) })` — and check it is not a derived |
| `on:click={f}`, `on:click\|preventDefault` | `onclick={f}`, and `e.preventDefault()` inside `f` |
| `createEventDispatcher` | a callback prop: `let { onselect } = $props()` |
| `<slot />`, `<slot name="x" let:item>` | `{@render children?.()}`, `{#snippet x(item)}` + `{@render x(item)}` |
| `use:action` | `{@attach fn}` (5.29+); `fromAction` wraps an old action |
| `new App({ target })`, `$destroy` | `mount(App, { target })`, `unmount(app)` |
| `spring()`, `tweened()` stores | `new Spring()`, `new Tween()` from `svelte/motion` |
| `$app/stores` (`$page`) | `$app/state` (`page`) — **removed in Kit 3**, deprecated since 2.12 |
| `svelte.config.js` with `kit: {}` | Kit 3: options passed to `sveltekit({...})` in `vite.config.ts`, no `kit` key |
| `$lib` | Kit 3: `#lib`, a Node subpath import in `package.json` `"imports"` |
| `$env/static/private`, `$env/dynamic/public`, … | Kit 3: `$app/env/private`, `$app/env/public`, declared in `src/env.ts` |
| `$app/environment` | Kit 3: `$app/env` (`browser`, `dev`, `building`, `version`) |
| `$service-worker` | Kit 3: `$app/manifest`, `version` from `$app/env`, `resolve` from `$app/paths` |
| `invalidateAll()`, `goto(u, { invalidateAll })` | Kit 3: `refreshAll()`, `goto(u, { refreshAll: true })` |
| `goto(u, { noScroll, keepFocus })` | Kit 3: `goto(u, { reset: false })` |
| `pushState`, `replaceState` | Kit 3: `goto(u, { state, shallow: true, replace? })` |
| `export const snapshot` | Kit 3: `snapshot({ capture, restore })` from `$app/navigation` |
| `csrf: { checkOrigin: false }` | Kit 3: `csrf: { trustedOrigins: [...] }` |
| `error(404, { message, ...extra })` | Kit 3: `error(404, 'message', { ...extra })` |

## 1. State: `$state`

- Only what changes and drives the UI is state. A constant is a `const`.
- Objects and arrays become deep proxies: `todos.push(t)` and `user.name = n` update the
  UI. Classes, `Map`, `Set`, `Date`, and `URL` do not — use `SvelteMap`, `SvelteSet`,
  `SvelteDate`, `SvelteURL` from `svelte/reactivity`, or replace the whole value.
- **Destructuring copies.** `let { name } = user` is a snapshot of `user.name` and never
  updates. Read `user.name` where it is used.
- **Passing a value passes a snapshot.** `track(count)` sees the number, not the state.
  Pass a getter (`() => count`) or the containing object.
- `$state.raw` for large data replaced as a whole — API responses, chart series, long lists.
  No proxy cost, but mutating it does nothing; reassign it.
- `$state.snapshot(x)` before handing state to anything outside Svelte: a chart library,
  `structuredClone`, `postMessage`, IndexedDB, `console.log`. Libraries choke on proxies.
- **Classes**: put `$state` on fields (`count = $state(0)`). A method passed as a handler
  loses `this` — `onclick={counter.inc}` breaks; use an arrow-function field or
  `onclick={() => counter.inc()}`.
- **Shared state** lives in a `.svelte.ts` (or `.svelte.js`) module — runes only work in
  `.svelte` and `.svelte.*` files. Export an object or class instance and mutate its
  properties. `export let count = $state(0)` cannot be reassigned by importers, and
  exporting a reassigned primitive breaks reactivity across modules.
- **Module-level state on the server is shared by every request.** With SSR, a
  `$state` (or any `let`) at module top level holds one user's data and serves it to the
  next. Per-user state goes in context, `event.locals`, or `load` data.

## 2. Derived values: `$derived`

- Anything computed from state is `$derived`, never an `$effect` that writes state.
  `let total = $derived(items.reduce((s, i) => s + i.qty, 0))`. For several lines,
  `$derived.by(() => { … return x })`.
- Deriveds are lazy, memoised, and pure. Writing state inside one is an error
  (`state_unsafe_mutation`). No fetches, no logging, no DOM.
- Dependencies are what the expression reads **synchronously**. A value read after an
  `await` or inside a callback is not tracked.
- `let { a, b } = $derived(obj)` stays reactive; destructuring the derived is fine.
- A derived can be assigned to (5.25+) for optimistic UI. It holds until a dependency
  changes, then recomputes. Do not use it as a second source of truth.
- Copying a prop into `$state` makes a local copy that stops following the parent. Do it
  only on purpose, name the prop `initialX`, and otherwise derive.

## 3. Effects: `$effect` is the escape hatch

Use an effect to keep something **outside** Svelte in step with state: a canvas, a chart
instance, a third-party widget, `document.title` outside `<svelte:head>`, a subscription,
`localStorage`. Not to compute state, and not to react to a user action.

- **Return a cleanup** for everything an effect starts: intervals, listeners, observers,
  sockets, `chart.dispose()`, an `AbortController`. It runs before the next run and on
  unmount.
- **If it happens because the user did something, do it in the handler**, not in an effect
  watching the state the handler changed.
- **Effects that fetch race.** The older response can land after the newer one. Abort in
  the cleanup, or pass `getAbortSignal()` from `svelte` to `fetch`. In SvelteKit, prefer a
  `load` function, which handles this for you.
- Only synchronous reads are tracked. Read every dependency before the first `await`, or
  in the effect body rather than in a timer callback. `untrack(() => x)` reads without
  depending.
- An effect that writes state it reads loops (`effect_update_depth_exceeded`). Usually it
  should have been a `$derived`.
- Effects do not run during SSR. `$effect.pre` runs before the DOM updates (autoscroll,
  measuring). `$effect.root` creates effects outside component init and returns its own
  cleanup — call it. `onMount` is still fine for once-on-mount work.

## 4. Props: `$props` and `$bindable`

```svelte
<script lang="ts">
	import type { Snippet } from 'svelte';
	import type { HTMLButtonAttributes } from 'svelte/elements';

	interface Props extends HTMLButtonAttributes {
		label: string;
		variant?: 'primary' | 'ghost';
		onselect?: (id: string) => void;
		children?: Snippet;
	}

	let { label, variant = 'primary', onselect, children, class: klass, ...rest }: Props = $props();
</script>

<button class={['btn', variant, klass]} {...rest}>{label}{@render children?.()}</button>
```

- Type every component's props with an interface. Wrappers extend the element's
  attributes from `svelte/elements` and spread `...rest` onto the element.
- **Data down, events up.** A child tells the parent through a callback prop. Two-way
  `bind:` on a component prop only works if the child declared it `$bindable()`; use it for
  form-like components, not as a shortcut.
- Mutating a prop object the child does not own warns (`ownership_invalid_mutation`) and
  makes the data flow impossible to follow. Call back instead.
- Fallback values (`items = []`) are not reactive proxies; a child that mutates them sees
  no update.
- `$props.id()` for ids that must match between server and client (`<label for>`,
  `aria-describedby`). Never `Math.random()` — it differs between SSR and hydration.
- `class` accepts arrays and objects (5.16+): `class={['row', selected && 'selected']}`.
  Prefer that over many `class:` directives. Let callers pass `class` through.

## 5. Events

- Event attributes: `onclick={handler}`. No modifiers; call `e.preventDefault()` and
  `e.stopPropagation()` in the handler. Capture is `onclickcapture`.
- `<svelte:window onkeydown={…}>` and `<svelte:document>` attach and remove listeners for
  you. Prefer them over `addEventListener` in `onMount`.
- Svelte delegates many events to the root. A manual `addEventListener` mixes badly with
  that ordering; use `on()` from `svelte/events`, which respects it and returns a remover.
- Never put an `onclick` on a `<div>` or `<span>` for something that acts like a button.
  Use `<button type="button">` or `<a href>` (see §13).

## 6. Snippets and children

- `children` is the default content: `{@render children?.()}`. Optional chaining unless the
  component cannot work without it.
- Named content is a snippet prop: declare `{#snippet row(item)}…{/snippet}` inside the
  component tag and it is passed as `row`. Type it `Snippet<[Item]>`.
- Snippets close over the scope where they are declared and can be passed around like
  values. A top-level snippet that uses only module-scope values can be exported from
  `<script module>` (5.5+).
- `<slot>` is legacy. Do not add one to a runes component.

## 7. Template

- **Key every `{#each}`** whose items can be inserted, removed, or reordered, or that hold
  component state, inputs, or transitions: `{#each rows as row (row.id)}`. The key is a
  stable unique id — never the index, never a value that can repeat (duplicates throw
  `each_key_duplicate`). Give an empty state with `{:else}`.
- `{#await p}…{:then v}…{:catch e}…{/await}` always has a `{:catch}`.
- `{#key x}` recreates its content when `x` changes — the honest way to reset a child.
- `{@const}` for a value used several times inside a block.
- `{@html}` turns off escaping. Never with anything a user, an API, or a model wrote,
  unless it went through a sanitiser (DOMPurify) at the last moment. Render text as text.
- `$inspect(x)` and `{@debug}` are for development. Remove them before committing.
- With `compilerOptions.experimental.async` on, `await` works in the template, in
  `$derived`, and at the top of a component's script, inside a `<svelte:boundary>` with a
  `pending` snippet. Still experimental in 5.57; do not use it unless the project already
  enabled it.

## 8. Bindings

- `bind:value`, `bind:checked`, `bind:group`, `bind:files`, `bind:this`.
- `bind:this` is `undefined` until mount. Use it in `$effect` or `onMount`, never at the top
  of the script.
- A number input binds a number; empty or invalid gives `undefined`, not `0`. Handle it.
- Function bindings (5.9+) validate or transform on the way in:
  `bind:value={() => text, (v) => (text = v.trimStart())}`.
- Dimension bindings (`bind:clientWidth`) are read-only and use a `ResizeObserver`; they do
  not see `display: inline` elements.

## 9. Context, stores, and shared state

- `setContext` / `getContext` only during component init. `createContext<T>()` (5.40+)
  gives a typed `[get, set]` pair; prefer it to string keys.
- Put a reactive object (or a getter) in context, not a primitive — a primitive is a
  snapshot and consumers never see it change.
- Context is per component tree and so per request on the server. It is the safe place for
  per-user state in SSR; module-level state is not (§1).
- `svelte/store` still works and `$store` still auto-subscribes in components. Use stores
  for streams and library interop; for app state, a `$state` class in a `.svelte.ts` file
  is simpler. `fromStore` / `toStore` bridge the two.
- `createSubscriber` (`svelte/reactivity`) turns an external event source into something
  reactive that starts and stops with its readers. `MediaQuery` and
  `svelte/reactivity/window` (`innerWidth`, `online`, …) already do this.

## 10. Attachments, actions, and third-party libraries

- `{@attach (node) => { … return cleanup }}` runs when the element mounts, reruns when the
  state it reads changes, and cleans up on unmount. It works on components that spread
  props onto an element. Prefer it to `use:` for new code.
- **Wrapping a library** (a chart, a map, an editor): create it in an attachment or
  `$effect`, push new data on change (`chart.setOption(...)` rather than rebuilding),
  dispose in the cleanup, and hand it `$state.snapshot(data)` or `$state.raw` data. Import
  it lazily (`await import(...)`) when it is heavy and not on the first screen. Size it
  from a `ResizeObserver` and dispose that too.
- Guard browser-only libraries from SSR: import them inside the effect, or check `browser`.

## 11. Styling

- Styles are scoped to the component. `:global(...)` only nested under a scoped class
  (`.prose :global(p)`), never bare — a bare global from a component leaks to every page.
- Theme children with CSS custom properties: `<Chart --line="var(--accent)" />`.
- `style:width="{w}px"` over string-built `style` attributes.
- The compiler warns about unused selectors. Delete them; do not silence the warning.
- Honour `prefersReducedMotion` (`svelte/motion`) in transitions and animations.
  Transitions are local by default; `|global` plays them when a parent block changes.

## 12. TypeScript

- `<script lang="ts">`. Only type syntax is stripped natively; `enum`, decorators, and
  constructor parameter properties need `vitePreprocess({ script: true })`. Prefer a union
  or an `as const` object.
- Generic components: `<script lang="ts" generics="T extends { id: string }">`.
- The component type is `Component<Props>` from `svelte`, not the `SvelteComponent` class.
- SvelteKit writes types per route in `./$types`: `PageProps`, `LayoutProps`, `PageLoad`,
  `PageServerLoad`, `Actions`, `RequestHandler`. Use them:
  `let { data }: PageProps = $props();`.
- Declare `App.Error`, `App.Locals`, `App.PageData`, `App.PageState`, `App.Platform` in
  `src/app.d.ts`.
- `tsc` does not check `.svelte` files. `svelte-check` does; run it, and treat its
  warnings (a11y included) as errors.
- An API's types written by hand drift from the API. Generate them, or check them at the
  boundary with a schema, or at least keep them in one file next to a link to the contract.

## 13. Accessibility

The compiler's `a11y_*` warnings are bugs. Fix them; a `<!-- svelte-ignore -->` needs a
comment saying why.

- Interactive things are `<button>` or `<a href>`. A `<div onclick>` cannot be reached by
  keyboard or understood by a screen reader.
- Every input has a label (`<label for={id}>` with `$props.id()`, or wrapping the input).
- Every page sets `<svelte:head><title>`. SvelteKit announces the title on navigation.
- A chart or an icon-only button has a text alternative.
- After a client-side change that moves the user's attention (a dialog, an error), move
  focus there.

## 14. SvelteKit: routes and files

| File | Runs | For |
|---|---|---|
| `+page.svelte`, `+layout.svelte` | server (SSR) and browser | the page; a layout renders `{@render children()}` |
| `+page.ts`, `+layout.ts` | server and browser | universal `load`; page options |
| `+page.server.ts`, `+layout.server.ts` | server only | `load` with secrets, DB, cookies; form `actions` |
| `+server.ts` | server only | an endpoint: `GET`, `POST`, … returning a `Response` |
| `+error.svelte` | both | the error page for its subtree |
| `hooks.server.ts` | server | `handle`, `handleError`, `handleFetch`, `init` |
| `hooks.client.ts` | browser | `handleError`, `init` |
| `hooks.ts` | both | `reroute`, `transport` |
| `params/*.ts` | both | param matchers: `[id=integer]` |
| `src/env.ts` | — | Kit 3: declares environment variables |

- Folders: `[param]`, `[[optional]]`, `[...rest]`, `(group)` for layouts without a URL
  segment, `+page@.svelte` to break out of a layout.
- **Server-only code**: any `*.server.*` file or any file under a `server/` directory
  (outside `src/routes`), plus `$app/env/private` (Kit 2: `*.server.*`, `src/lib/server/`,
  and `$env/*/private`). SvelteKit refuses to build if browser
  code imports one. Database clients, secrets, and API keys live only there.
- **Page options** — `ssr`, `csr`, `prerender`, `trailingSlash` — are exported from
  `+page.ts`/`+layout.ts` (or their `.server` versions) and inherited downward. An SPA sets
  `ssr = false` in the root layout and uses `adapter-static` with a `fallback` page. A static
  site prerenders everything.
- **With adapter-static, nothing on the server runs after the build.** `+page.server.ts`,
  `+server.ts`, actions, and `hooks.server.ts` only run while prerendering. An SPA talks
  to its API with `fetch` from a universal `load`.
- **Links** are plain `<a href>`. Build them with `resolve()` from `$app/paths` so a base
  path keeps working. Kit 3: a route id with a leading slash plus params,
  `resolve('/ticker/[t]', { t })`; a pathname without one, `resolve('about')`. Static files
  through `asset('logo.svg')` — no leading slash in Kit 3.
- `page` from `$app/state` gives `url`, `params`, `route.id`, `status`, `error`, `data`,
  `form`, `state`. It is reactive in runes; read it where it is used.

## 15. Loading data

- `load` returns a plain object; the page gets it as `data`. Reach for a `load` before an
  `$effect` that fetches.
- **Universal or server?** A server `load` for secrets, the database, cookies, or private
  APIs. A universal `load` when it can call a public API from either side, or returns
  things that cannot be serialised (a component, a class instance). Server-load data must
  survive `devalue` — `Date`, `Map`, `Set`, `BigInt` do; class instances and functions need
  a `transport` hook.
- **Everything a server `load` returns is sent to the browser** and embedded in the HTML.
  Return the fields the page shows, never the whole row.
- **Use the `fetch` you are given** (`event.fetch`): relative URLs work on the server,
  cookies are forwarded, and responses made during SSR are inlined so hydration does not
  fetch twice. Global `fetch` with a relative URL fails on the server.
- **No waterfalls.** Start independent requests together (`Promise.all`). `await parent()`
  after starting your own requests, not before.
- **Streaming**: a server `load` can return a promise un-awaited, and the page renders it
  with `{#await}`. Attach `.catch` or handle it in `{:catch}`; an unhandled rejection can
  crash the server. Needs `csr` on.
- `error(404, 'Not found')` and `redirect(303, '/login')` throw. Do not wrap them in a
  `try/catch` that swallows them — rethrow when `isHttpError(e) || isRedirect(e)`. `fail()`
  is the opposite: it is returned, and `throw fail()` is an error. `redirect` to an external
  URL needs `{ external: true }` or an origin allowlist (Kit 3); never redirect to a URL
  taken from the query string unchecked.
- **Rerunning**: `load` reruns when what it read changes — `params`, `url.searchParams`,
  `parent()`, a `depends('app:key')`. Mark custom dependencies with `depends('app:key')` and
  rerun with `invalidate('app:key')`; rerun everything with `refreshAll()` (Kit 3).
  `untrack(() => url.pathname)` reads without depending.
- `data` changes when the user navigates between two pages of the same route, but the
  component is reused, not recreated. State initialised from `data` once at the top of
  the script goes stale — derive from it, or `{#key page.url.pathname}`.

## 16. Forms and mutations

- **Form actions** live in `+page.server.ts`: `export const actions = { create: async
  ({ request, locals }) => { … } }`, posted to with `<form method="POST" action="?/create">`.
  Validate every field on the server. On a validation failure, `return fail(400, { values,
  errors })` and never echo a password back. On success, `redirect(303, …)` or return a
  small object.
- `use:enhance` from `$app/forms` keeps the form working without JavaScript and avoids the
  full reload. In a custom callback, call `update()` (Kit 3: `update({ refreshAll })`) or
  the page will not reflect the result. Needs `method="POST"`; file inputs need
  `enctype="multipart/form-data"`.
- **Remote functions** (`experimental.remoteFunctions: true`) are `*.remote.ts` files
  exporting `query`, `query.batch`, `query.live`, `form`, `command`, and `prerender` from
  `$app/server`. Each one is a public HTTP endpoint:
  - validate the argument with a Standard Schema (Valibot, Zod); `'unchecked'` only when
    any value is truly acceptable;
  - authorise inside the function — a layout's check does not cover it;
  - a remote `form` reports problems with `invalid(...)`, not `fail(...)`;
  - the API is experimental and changed in minor releases; check the installed types.
- A `+server.ts` endpoint authenticates and authorises itself; nothing above it in the
  route tree runs for it.

## 17. Hooks, auth, cookies

- `handle` authenticates once and puts the user on `event.locals`. **Authorise where the
  data is read or written** — in each server `load`, action, endpoint, and remote function,
  or centrally in `handle` by path. A check in `+layout.server.ts` alone does not protect
  actions, endpoints, or remote functions, and it does not rerun on every navigation.
- `handleError` logs the real error and returns only `{ message: 'Internal Error', id }`.
  Stack traces and SQL never reach the client.
- `cookies.set(name, value, { path: '/', httpOnly: true, secure: true, sameSite: 'lax' })`.
  Always pass `path`; without it the cookie is scoped to the current route.
- CSRF: SvelteKit checks `Origin` on form posts. Add trusted origins to
  `csrf.trustedOrigins` (Kit 3) one by one; `['*']` turns the protection off.
- CSP: the `csp` option (`mode: 'auto'`) adds hashes or nonces for SvelteKit's own inline
  scripts. A hand-written inline script in `app.html` needs `nonce="%sveltekit.nonce%"`.
- `getRequestEvent()` from `$app/server` reads the current request inside helpers called
  from a `load`, action, or remote function.

## 18. Environment and config

- **Kit 3** reads its options from `sveltekit({...})` in `vite.config.ts`: `adapter`,
  `alias`, `csp`, `csrf`, `paths`, `prerender`, `router`, `version`, `compilerOptions`. A
  `svelte.config.js` is an error. **Kit 2** reads `svelte.config.js` and its `kit: {}`.
- **Kit 3 variables** are declared in `src/env.ts` with `defineEnvVars` from
  `@sveltejs/kit/env`: `public: true` makes one importable from `$app/env/public`; the
  default is private, from `$app/env/private` (server-only). `static: true` inlines the
  build-time value; otherwise it is read at startup. A `schema` validates it at startup.
  **Kit 2** uses `$env/static|dynamic/private|public` and the `PUBLIC_` prefix.
- **`import.meta.env.VITE_*` is inlined into the browser bundle.** Anything behind
  `VITE_` — or `public: true`, or `PUBLIC_` — is public. A secret never goes there.
- Read Vite-only settings (dev proxy target, credentials for it) with `loadEnv` inside
  `vite.config.ts`; they never reach the bundle.
- `browser`, `dev`, `building`, `version` from `$app/env` (Kit 3) or `$app/environment`
  (Kit 2). Code that touches `window`, `document`, or `localStorage` at the top of a
  component or in a universal `load` crashes SSR; guard it with `browser` or move it into
  `onMount` / `$effect`.

## 19. Performance

- `$state.raw` for big data you replace; deep proxies on thousands of objects cost memory
  and time.
- Key `{#each}` (§7). Paginate or virtualise lists in the thousands.
- Import heavy libraries per part (`echarts/core` plus the charts you use) and lazily when
  they are not on the first screen. Nothing heavy in the root layout.
- A `$derived` over a big array recomputes on every change it reads. Narrow what it reads,
  or debounce the input that drives it.
- Keep `data-sveltekit-preload-data="hover"` (the template default) so navigation starts
  before the click.
- Hydration mismatches — `Date.now()`, `Math.random()`, `toLocaleString()` with a different
  locale or time zone on the server — cost a re-render and show wrong content first. Format
  dates with an explicit locale and `timeZone`, or only in the browser.

## 20. Testing

- Logic goes in plain `.ts` or `.svelte.ts` modules and is tested without a DOM.
- A test that uses runes is named `*.svelte.test.ts`. Wrap state in `$effect.root(...)`
  and call `flushSync()` before asserting on effects; call the root's cleanup at the end.
- Components: `@testing-library/svelte` in jsdom or happy-dom, or Vitest browser mode with
  `vitest-browser-svelte`. Query by role and label, the way a user finds things. `mount`,
  `unmount`, and `flushSync` from `svelte` for low-level tests; `render` from
  `svelte/server` for SSR output.
- End-to-end: Playwright against `vite build && vite preview`, not the dev server.
- Test the code where a wrong answer still looks right: formatting money and dates,
  mapping API data to chart options, form validation.

## Before calling it done

```
npx svelte-check --tsconfig ./tsconfig.json --fail-on-warnings   # types, a11y, unused CSS
npx vitest run
npx vite build                                                     # server-only imports, prerender errors
npx vite preview                                                   # the built app, not the dev server

# legacy or removed syntax that should not be in new code
rg -n 'export let |^\s*\$:|on:[a-z]+=|createEventDispatcher|<slot|\$app/stores' src
rg -n '\{@html' src                                                 # each one needs a sanitiser or a reason
```

Click through the changed pages in the built preview with the network tab open: no failed
requests, no console warnings, no request repeated after hydration.
