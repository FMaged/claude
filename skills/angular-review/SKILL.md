---
name: angular-review
description: Use when reviewing an Angular app — components and templates, services, signals and resources, interceptors and guards, routes, angular.json and the build configurations, config.json loading, the web.config or nginx config that serves the build, or the specs (e.g. "review my Angular component", "check this Angular app before I merge", "is this component safe from XSS?", "why does this view not update?", "does anything here leak a token?", "will the same build work on staging and prod?"). Reports what leaks, what breaks build-once, what stops updating or leaks memory, what is slow, XSS, what is untested, and basic accessibility, with the file and line. Not for AngularJS 1.x.
---

# Angular Review

Review the components and their templates, services, interceptors, guards, routes,
`main.ts`, `angular.json`, `package.json`, the `tsconfig*.json` files, `eslint.config.js`,
`public/` (`web.config`, a local `config.json`), the nginx config and Dockerfile that serve
the build, and the specs. Report problems. Do not rewrite unless the user asks.

A frontend fails in ways a diff hides. Everything in the bundle is public, so a key in an
environment file is published. A build-time switch makes the build that passed staging
different from the one on prod. A view that stops updating, a subscription that never
ends, and an `innerHTML` with API data all pass a quick look and every test that does not
check them. What matters most: nothing secret ships to the browser, one build serves every
environment, the view shows the current state, and no data reaches the page as markup.
The writing rules are in the `angular` skill.

Other reviews own their part: what the API allows each user is `web-security-review`, the
API's code is `dotnet-review`, the Dockerfile is `docker-review`, and the pipeline is
`gitlab-ci-review`. Name them where a finding needs them, and stay on the Angular side.

## 0. Read the setup first

- **The version** in `package.json`. Angular 22 is current; a major gets fixes for 18
  months, so 19 and older get none, and 20 leaves support at the end of November 2026.
  Should fix, with the update as its own task (`npx ng update`, one major at a time).
- **Zoneless or `zone.js`:** `zone.js` in `polyfills` in `angular.json` means a zone-based
  app, where a plain field set in a callback still updates the view outside OnPush
  components. Without it, section 3 applies to every component.
- **`angular.json`:** the builder (`@angular/build:application`, or the old
  `@angular-devkit/build-angular` ones), `fileReplacements`, every build configuration and
  what it changes, the budgets, the assets of the production configuration, `sourceMap`.
- **The hosts:** `public/web.config` (IIS), an nginx site, a Dockerfile. Section 7 depends
  on which exist.
- In a diff, read the whole component, its template, its route, and its providers, not
  only the changed lines: a missing `track`, an eager route, or an interceptor that sees
  every request is often outside the hunk.

## 1. What leaks

Everything in the bundles and in `config.json` can be read by anyone who opens the app.

- **A secret in what ships:** an API key with write rights, an OIDC client secret (a
  browser app is a public client and has none), a password, a private key, or a
  service token, in `src/environments/`, `config.json`, a constant, a `define` in
  `angular.json`, or a `.env` read at build time. Blocker. A key meant to be public (an
  OIDC client id, a maps key restricted to the site) is fine.
- **Credentials sent to any origin:** an interceptor that adds `Authorization` or
  `withCredentials` to every request, or checks the URL loosely: `req.url.includes('api')`,
  or `startsWith(apiUrl)` without the trailing `/`, which also matches
  `https://api.example.com.attacker.net`. The token goes to every third-party URL the app
  calls. Blocker.
- **Tokens stored without reason:** an access or refresh token in `localStorage` or
  `sessionStorage`, or in a cookie set from script (not HttpOnly). Any injected script reads
  it, and it outlives the tab. A session cookie set by the API, or a token in memory only.
  Should fix; blocker for a long-lived refresh token in `localStorage`.
- **A token or personal data in a URL** (a query parameter after login, a link with an
  e-mail address): it lands in server logs, browser history, and the `Referer` of the next
  request. Should fix.
- **Logs:** `console.log` of a user, a token, or a response, left in production code, or the
  same values sent to an error tracker. Should fix.
- **Personal data left in storage after logout:** the app clears what it stored. Should fix.
- **Source maps in production** (`sourceMap: true` in the production configuration without
  `hidden`): the original code and its comments are public. Should fix unless the code is
  public anyway.

## 2. What breaks build-once

The pipeline builds once and deploys the same files to staging and prod (`gitlab-ci`).
Blocker for each of these:

- `src/environments/` files whose values differ between staging and prod (an API URL, a
  login authority), with `fileReplacements` in `angular.json`.
- A `staging` build configuration, `--configuration staging` in a script or job, or a
  `define` with an environment value.
- **`config.json` in the production build:** `public/config.json` without the asset
  `ignore` in the production configuration, or a `config.json` copied into the image.
  Every deploy then overwrites the host's file, so prod runs with the local values.

Should fix:

- `environment.production` or `isDevMode()` choosing a value or a behaviour that differs
  between staging and prod. Telling `ng serve` from a deployed build is fine.
- **`config.json` used without a check:** a missing key becomes a request to
  `undefined/orders` later, instead of a stop at start that names the key.
- **The config loaded with `provideAppInitializer` through `HttpClient`** while an
  interceptor reads the config: the interceptor runs before the config exists.
- **`config.json` that can be cached:** fetched without `cache: 'no-store'`, or served
  without `no-cache` (section 7). A changed value reaches users days later.
- `--base-href` or `<base href>` that differs per environment.

## 3. What stops updating

In a zoneless app, and in every OnPush component (the default in Angular 22), the view
updates only when a signal it reads changes, a template event runs, or something calls
`markForCheck()`. Should fix for each:

- **A plain field set in a callback:** in a `subscribe`, a `setTimeout`, a `.then`, or a
  listener added in code. The data arrives and the page does not show it. A signal, or
  `toSignal()`.
- **A signal changed in place:** `items().push(x)`, `user().name = 'x'`, or `set()` with the
  same object after changing it. The signal sees the same reference and nothing updates.
  `update((list) => [...list, x])`.
- **`effect()` that writes signals** to keep one value in step with another. It runs a turn
  late and can loop. `computed()`, or `linkedSignal()` for a value the user can also
  change.
- **`resource.value()` read while the resource is in error:** it throws, and the template
  breaks. Check `error()` or `hasValue()` first.
- **`@for` with a `track` that changes:** `track $index` on a list that is sorted, filtered,
  or refreshed, or `track item` on objects that a refresh replaces. Each change rebuilds
  the rows, and a row loses its focus and typed input. `track item.id`.
- **`ChangeDetectionStrategy.Eager`** (or the old `Default`) added to make an update show.
  It hides the bug above; nit unless it is the only fix in the change.
- A function call in a template that does real work (filtering, sorting): it runs on every
  check. `computed()`. Nit unless the work is heavy.

## 4. What leaks memory

- **A subscription that outlives its component:** `subscribe()` on a router event, a form's
  `valueChanges`, an `interval`, a store, or a service's subject, with no
  `takeUntilDestroyed()`, `toSignal()`, or `async` pipe. Every visit to the page adds one
  more, and the old ones still run their code. Should fix. One `http.get().subscribe()` ends
  by itself; `takeUntilDestroyed()` there only cancels a request the user left.
- **`takeUntilDestroyed()` outside an injection context** (in `ngOnInit`, in a method)
  without a `DestroyRef` argument: it throws NG0203 at run time. Should fix.
- **Listeners and timers added in code:** `addEventListener` on `window` or `document`,
  `setInterval`, a `ResizeObserver`, a chart instance, with no removal in
  `DestroyRef.onDestroy()`. Should fix.
- **A root service that keeps per-page data:** a `Map` or array filled by every visit and
  never cleared, or a subject that holds large responses. Nit, unless it grows without
  bound.

## 5. XSS

Angular escapes `{{ }}` and sanitizes `[innerHTML]`, `[href]`, and `[src]`. The holes are
where code turns that off or goes around it.

- **`bypassSecurityTrustHtml`, `…Url`, `…ResourceUrl`, `…Script`, or `…Style`** on any value
  that is not a constant in the code: data from the API, a user, the URL, or
  `config.json`. Blocker.
- **The DOM written directly:** `nativeElement.innerHTML =`, `outerHTML`,
  `insertAdjacentHTML`, `document.write`, or `Renderer2.setProperty(el, 'innerHTML', …)`.
  Nothing sanitizes these. Blocker with data from outside the code.
- **`[innerHTML]` with data from the API or a user.** Angular strips scripts, but the
  markup still lets someone add links, images, and forms to the page. Should fix: show it
  as text, or let the API send sanitized HTML from a known editor.
- **Navigation to a URL from outside:** `window.location.href = returnUrl`, `window.open(url)`,
  or `location.assign` with a query parameter or API value. A `javascript:` URL runs, and
  any other URL is an open redirect. `router.navigateByUrl(returnUrl)` stays inside the
  app and is safe. Should fix; blocker when it takes `javascript:`.
- **An `<iframe [src]>` or `<script>`** whose URL comes from data: it needs
  `bypassSecurityTrustResourceUrl`, which is the blocker above.
- **A third-party script in `index.html`** from a CDN without `integrity`, or added at run
  time: it runs with the user's session. Should fix.
- **No Content-Security-Policy** on the host: one more line of defence is missing. Say so
  once as should-fix and hand the policy to `web-security-review`.

## 6. What is slow

- **A feature route loaded eagerly:** `component:` instead of `loadComponent` or
  `loadChildren` in the routes, or a feature imported into the root component. Its code
  is in the first load of every page. Should fix.
- **Budgets raised or removed** in `angular.json` to make the build pass, or an initial
  budget far above 1 MB. Should fix: the growth is the finding, and a lazy route or a
  smaller package is the fix.
- **A heavy package in the first load:** a chart or editor library in the root, `moment`
  with every locale, a whole icon set, `import * as _ from 'lodash'`. Should fix; `@defer`
  for a heavy part below the fold.
- **Requests the user did not need:** one request per row (a loop of `get`s), search as you
  type without `debounceTime` and `switchMap`, polling every second, the same data loaded
  by three components. Should fix.
- **A production build that is not one:** `optimization: false` or `outputHashing` other
  than `all` in the production configuration. Unhashed names are either never cached or
  cached past the next deploy. Should fix.
- A list of thousands of rows rendered at once: virtual scrolling or paging. Nit, unless
  the list is a main page.
- Large images without `NgOptimizedImage` (`ngSrc`). Nit.

## 7. Serving the build

- **No rewrite to `index.html`:** a reload or a shared link on `/orders/1` gets the
  server's 404. Should fix.
- **A rewrite that also catches missing scripts:** after a deploy, a browser with the old
  `index.html` asks for a chunk that is gone and gets `index.html` back, a MIME type error
  instead of a 404. Should fix.
- **Caching:** `index.html` or `config.json` served without `no-cache`, or a long cache or
  `immutable` on names without a content hash (`favicon.ico`, files from `public/`). Users
  run the old build after a deploy. Should fix.
- **nginx:** an `add_header` in a `location` drops every `add_header` from the `server`
  block, so security headers vanish on some responses. Should fix.
- **IIS:** the `web.config` rewrite needs the URL Rewrite module on the host; without it
  the site answers 500.19. Name the check.
- **The deploy deletes the host's `config.json`:** an msdeploy sync without a `-skip` rule
  for it, or an `rsync --delete` into the folder that holds it. The app stops starting
  after the first deploy. Blocker; the job itself is for `gitlab-ci-review`.

## 8. What is untested

- **No specs,** or only the generated "should create". Should fix.
- **Tests that cannot fail:**
  - An `expect` inside a `subscribe` or callback that never runs.
  - An async test that does not `await` the work.
  - An assertion before `await fixture.whenStable()`: it checks the old view, and a test
    for "the error is not shown" always passes.
  - `toBeTruthy()` on a value that is always truthy.
  - `it.only`, `describe.only`, `fit`, or `fdescribe` left in: CI runs that one test and
    skips the rest.
  - `it.skip` or `xit` with no reason.

  Should fix.
- **Real requests in tests:** no `provideHttpClientTesting()`, or a test that needs
  `public/config.json` or a running API. Should fix. No
  `HttpTestingController.verify()`: an unexpected request goes unnoticed; nit.
- **`fakeAsync` in a zoneless app:** it needs `zone.js`. Vitest's `vi.useFakeTimers()`.
  Should fix.
- **Paths with no test,** where they matter: the config check with a missing key, each
  interceptor (credentials for the API only, the 401 handling), each guard, the error
  state of each component that loads data, form validation, and the code the change
  touched. Name the missing tests; do not ask for coverage numbers.

## 9. Accessibility

`ng lint` with angular-eslint's template accessibility rules finds much of this; do not
list what it already reports, but flag the rules being turned off.

- **A click handler on a `div` or `span`** with no keyboard handler, role, or `tabindex`:
  keyboard users cannot use it. A `<button>`. Should fix.
- **Missing names:** an `<img>` without `alt`, an icon-only button without `aria-label`, a
  form control without a `<label>` (a placeholder is not one). Should fix.
- **Focus hidden:** `outline: none` on `:focus` with nothing in its place. Should fix.
- **Status that only shows:** loading and error messages without `role="alert"` or
  `aria-live`, so a screen reader says nothing. Nit, should fix for errors.
- `angular.configs.templateAccessibility` removed from `eslint.config.js`, or its rules
  off. Should fix.
- Colour as the only signal (a red border for an error, no text). Nit.

## 10. Strictness and packages

- **Strictness turned off:** `"strict": false`, `strictTemplates: false`, `noImplicitAny`
  off, or `as any`, `@ts-ignore`, `@ts-expect-error`, and `$any()` in templates to silence
  an error. Should fix.
- **A known vulnerable package** (`npm audit --omit=dev`): high or critical in what ships,
  blocker; in build tools, should fix.
- **No `package-lock.json`,** or a CI job that runs `npm install` instead of `npm ci`. CI
  then builds with versions nobody tested. Should fix.
- **Abandoned or duplicate packages:** a wrapper whose last release predates the app's
  Angular major, `zone.js` still in a zoneless app, two date or HTTP libraries. Nit.

## Commands

```
npm ci
npx ng lint
npx ng test --watch=false
npx ng build
npm audit --omit=dev
grep -rnE 'bypassSecurityTrust|innerHTML|outerHTML|insertAdjacentHTML|document\.write' src/
grep -rnE 'localStorage|sessionStorage|location\.href|window\.open' src/
grep -rnE '\.subscribe\(' src/
grep -n 'fileReplacements\|"sourceMap"\|budgets' angular.json; ls src/environments
find dist -name '*.map'; ls dist/*/browser/config.json
curl -sI https://<host>/orders/1; curl -sI https://<host>/no-such-chunk.js
```

The greps list lines to read, not findings: a `subscribe` with `takeUntilDestroyed()` is
fine. The build prints the budget results. The two `curl` calls show the deep-link
rewrite (200, `no-cache`) and the missing-file case (404). Skip what `ng lint` and the
compiler report on their own when the build is clean; say "run `ng lint`" in one line
instead.

## How to report

Most serious first, as a list:

```
<file>:<line> — <blocker | should fix | nit>: <what is wrong and what the user sees>
Fix: <the change, one line>
```

A blocker ships a secret to the browser, sends credentials to another origin, lets data
reach the page as markup or script, makes the build differ per environment (or ships
`config.json` in it), or ships a high or critical vulnerable package. A should-fix shows
stale data or leaks memory, stores a token where script can read it, slows every first
load, breaks deep links or caching, leaves a path untested or a test that cannot fail, or
shuts out keyboard and screen reader users. A nit is tidiness. If the code is fine, say so
in one sentence and name the two or three things you checked hardest. Do not invent
findings to fill a list. If you add a comment as part of a fix, follow the `code-comments`
skill.
