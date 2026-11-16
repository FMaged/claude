---
name: angular
description: Use when writing or changing an Angular app on the current major (22) — standalone components, signals and resources, the @if and @for control flow, inject(), OnPush and zoneless change detection, strict TypeScript, lazy routes, functional HTTP interceptors, configuration read at start from a config.json next to the app instead of build-time environment files, Vitest tests through ng test, angular-eslint, ng build with budgets, and deploying the one build as static files on IIS with a web.config rewrite, on nginx with try_files, or in an nginx Docker image (e.g. "start a new Angular app", "add a lazy route", "load the API URL at run time", "why does a page reload give a 404 on the server", "add an auth interceptor", "make this component use signals", "write a test for this component", "deploy the Angular build to IIS and nginx"). For the pipeline that builds and deploys it, use gitlab-ci; for the API behind it, use dotnet; for reviewing Angular code, use angular-review.
---

# Angular

Write the app so one production build runs in every environment and on every host kind.
The pipeline builds it once and deploys the same files to staging and then prod
(`gitlab-ci`, section 4). So nothing that differs between environments may be in the
build: no `environment.prod.ts`, no API URL, no per-environment build configuration.
Most Angular trouble in production is one of these: a value baked in at build time, a
page reload that gives the server's 404, an old `index.html` still cached after a deploy,
or a deploy that deleted the host's configuration.

The pipeline is `gitlab-ci`; the hosts (IIS, nginx, Docker) are prepared by `ansible`;
the compose file and the image's way through the registry are `docker`; the API behind
the app is `dotnet`. For who may see what, `web-security-review`. For a
review of finished code, the `angular-review` skill, or the `angular-reviewer` agent for a
check that runs unattended. For comments, `code-comments`. The worked example is `evals/examples/angular/` in the skills
repo: `orders-web`, a new app with one lazy route and the config loader, which reads an
order from the `Orders.Api` of `evals/examples/dotnet/`.

## 0. Check what is there

- `npx ng version`: the Angular and CLI versions of this project. Always run the CLI
  through `npx`, so the project's own version runs, not a global install.
- **Node.** Angular 22 needs Node `^22.22.3`, `^24.15.0`, or `>=26`. The CI image is
  `node:24.22.3`; use the same major locally.
- In an existing app, look for what this skill replaces: `src/environments/` and
  `fileReplacements` in `angular.json`, NgModules, `zone.js` in `polyfills`,
  `*ngIf` and `*ngFor`, Karma, and the old `@angular-devkit/build-angular` builders.
  `npx ng update @angular/core @angular/cli` moves one major at a time and runs the
  migrations; do not jump majors by editing `package.json`.

## 1. A new app

```
npx @angular/cli@22 new orders-web --style css --ssr false
cd orders-web
npx ng add angular-eslint
```

Angular 22's `ng new` already gives standalone components, zoneless change detection,
strict TypeScript and strict templates, routing, and Vitest. Keep all of them.

```
package.json, package-lock.json  commit the lock file; CI installs with npm ci
angular.json
tsconfig.json, tsconfig.app.json, tsconfig.spec.json
eslint.config.js
public/                    copied into the build as is: web.config, favicon
public/config.json         local values for ng serve; left out of the production build
src/main.ts                loads config.json, then starts the app
src/app/app.ts, app.config.ts, app.routes.ts
src/app/config.ts          the config type, its check, and its injection token
src/app/orders/            one folder per feature, loaded lazily
deploy/nginx.conf          the site for a Linux host
Dockerfile, deploy/nginx-docker.conf
```

- File names follow the 2025 style guide that `ng generate` uses: `order-page.ts` with
  the class `OrderPage`, no `.component` suffix.
- Do not turn strictness down (`strict`, `strictTemplates`, `noPropertyAccessFromIndexSignature`)
  to make an error go away. TypeScript 6 is strict by default, which is why the generated
  `tsconfig.json` does not say `"strict": true`.

## 2. Configuration at run time

The app reads everything that differs per environment from `config.json`, a file next
to `index.html` that each host provides. The build never contains it.

```ts
// src/app/config.ts
import { InjectionToken } from '@angular/core';

export interface AppConfig {
  readonly apiUrl: string;
  readonly environment: string;
}

export const APP_CONFIG = new InjectionToken<AppConfig>('APP_CONFIG');

// config.json comes from the server, so check it before the app relies on it.
export function parseConfig(json: unknown): AppConfig {
  const config = (json ?? {}) as Partial<AppConfig>;
  if (typeof config.apiUrl !== 'string' || config.apiUrl === '') {
    throw new Error('config.json has no apiUrl');
  }
  if (typeof config.environment !== 'string' || config.environment === '') {
    throw new Error('config.json has no environment');
  }
  return { apiUrl: config.apiUrl.replace(/\/+$/, ''), environment: config.environment };
}
```

```ts
// src/main.ts
import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { App } from './app/app';
import { APP_CONFIG, parseConfig } from './app/config';

// Each server provides its own config.json, so one build serves every environment.
fetch('config.json', { cache: 'no-store' })
  .then((response) => {
    if (!response.ok) {
      throw new Error(`config.json: HTTP ${response.status}`);
    }
    return response.json();
  })
  .then((json: unknown) =>
    bootstrapApplication(App, {
      ...appConfig,
      providers: [...appConfig.providers, { provide: APP_CONFIG, useValue: parseConfig(json) }],
    }),
  )
  .catch((err: unknown) => {
    console.error(err);
    document.body.textContent = 'The app could not start. Reload the page, or contact support.';
  });
```

- **No `src/environments/`, no `fileReplacements`, no `--configuration staging`.** Each
  of these makes a build per environment, so the build that passed on staging is not
  the one that runs on prod. The `development` and `production` build configurations
  are fine: they choose optimization, not values.
- **Why `fetch` in `main.ts`** and not `provideAppInitializer` with `HttpClient`: the
  interceptors need the config (the API URL), and an initializer's request would pass
  through them before the config exists. A plain `fetch` has no interceptors, and a
  failure shows a message instead of a blank page.
- **`cache: 'no-store'`**, and the server sends `config.json` with `no-cache`
  (section 7), so a changed value reaches users at their next page load.
- **Only public values.** Everyone who opens the app can read `config.json` and the
  bundles: the API URL, the login authority and client id, the environment name, and
  feature switches. Never a secret or an API key. A browser cannot keep one; the API
  holds secrets.
- **Who writes it:** Ansible, per host. Linux: `/etc/orders-web/config.json`, which nginx
  serves at `/config.json`. IIS: the file in the site folder, which the deploy skips.
  Docker: a file on the host, mounted by compose. The deploy job never writes it, so a
  rollback cannot bring back old values.
- **Locally**, `public/config.json` holds the `ng serve` values (the API on localhost).
  The production configuration leaves it out of the build:

```json
// angular.json, projects.orders-web.architect.build.configurations.production
"assets": [{ "glob": "**/*", "input": "public", "ignore": ["config.json"] }]
```

- `parseConfig` checks every key, so a missing value stops the start with its name,
  instead of a request to `undefined/orders` later.

## 3. Components and state

```ts
// src/app/orders/order-page.ts
import { Component, inject, input } from '@angular/core';
import { httpResource } from '@angular/common/http';
import { APP_CONFIG } from '../config';

interface Order {
  readonly id: number;
  readonly name: string;
}

@Component({
  selector: 'app-order-page',
  template: `
    @if (order.error()) {
      <p role="alert">Order {{ id() }} could not be loaded.</p>
    } @else if (order.isLoading()) {
      <p>Loading…</p>
    } @else {
      <h1>{{ order.value()?.name }}</h1>
    }
  `,
})
export class OrderPage {
  // The route parameter :id, bound by withComponentInputBinding().
  readonly id = input.required<string>();

  private readonly apiUrl = inject(APP_CONFIG).apiUrl;

  protected readonly order = httpResource<Order>(
    () => `${this.apiUrl}/orders/${encodeURIComponent(this.id())}`,
  );
}
```

- **OnPush is the default in Angular 22,** so a component needs no `changeDetection` line.
  `ChangeDetectionStrategy.Eager` (the old `Default`) only for a component that cannot be
  changed yet.
- **Zoneless.** There is no `zone.js`, so the view updates when a signal it reads changes,
  a template event handler runs, or `markForCheck()` is called. A plain field set in a
  `subscribe`, a `setTimeout`, or a `.then` does not update the view: make it a signal.
- **Signals for state:** `signal()`, `computed()` for values derived from others,
  `linkedSignal()` for a value that resets when another changes. Inputs and outputs are
  `input()`, `input.required()`, `output()`, and `model()`; queries are `viewChild()`.
- **Never change a signal's value in place.** `items().push(x)` changes the array but not
  the signal, so nothing updates. `items.update((list) => [...list, x])`.
- **`effect()` only to reach outside Angular** (local storage, a chart library), never to
  copy one signal into another: that is `computed()` or `linkedSignal()`.
- **Reading data: `httpResource()`** (stable in 22), which requests again when a signal it
  reads changes and cancels the old request. `value()` throws while the resource is in
  error, so check `error()` first, as above. Writes go through `HttpClient`.
- **RxJS** where a stream is the natural shape (search as you type). Show it with
  `toSignal()`; end a manual `subscribe` with `takeUntilDestroyed()`.
- **`inject()`** in field initializers, not constructor parameters.
- **Control flow:** `@if`, `@for` with `track` on a stable id (`track order.id`, not
  `$index`, when the list can change), `@switch`, `@let`, and `@defer` for heavy parts
  below the fold. `*ngIf` and `*ngFor` are deprecated since 20.
- **No `innerHTML` with data from the API or the URL,** and no `bypassSecurityTrust…` on
  it. Angular escapes interpolation; these turn that off.

## 4. Routes

```ts
// src/app/app.routes.ts
import { Routes } from '@angular/router';

export const routes: Routes = [
  {
    path: 'orders/:id',
    loadComponent: () => import('./orders/order-page').then((m) => m.OrderPage),
  },
];
```

```ts
// src/app/app.config.ts
import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideRouter, withComponentInputBinding } from '@angular/router';
import { apiInterceptor } from './api.interceptor';
import { routes } from './app.routes';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideHttpClient(withInterceptors([apiInterceptor])),
    provideRouter(routes, withComponentInputBinding()),
  ],
};
```

- **Every feature is a lazy route** (`loadComponent`, or `loadChildren` for a group), so
  its code loads when someone opens it and the first load stays inside the budget.
- **`withComponentInputBinding()`** hands route and query parameters to `input()`s; no
  `ActivatedRoute` subscriptions.
- **Unknown paths:** once the app has more than one page, a last `{ path: '**' }` route to a
  lazy not-found component. Never `redirectTo` a path that no route matches.
- **A guard (`CanActivateFn`) only hides what a user cannot use.** Anyone can call the API
  without the app, so the API checks every permission itself.
- Routes need the server's help on reload: any path that is not a file must return
  `index.html` (section 7).

## 5. HTTP interceptors

Functions, registered with `withInterceptors` (section 4).

```ts
// src/app/api.interceptor.ts
import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';
import { APP_CONFIG } from './config';

export const apiInterceptor: HttpInterceptorFn = (req, next) => {
  const { apiUrl } = inject(APP_CONFIG);
  const router = inject(Router);
  // The session cookie goes to our API only, never to another origin.
  if (!req.url.startsWith(`${apiUrl}/`)) {
    return next(req);
  }
  return next(req.clone({ withCredentials: true })).pipe(
    catchError((error: unknown) => {
      if (error instanceof HttpErrorResponse && error.status === 401) {
        void router.navigate(['/login'], { queryParams: { returnUrl: router.url } });
      }
      return throwError(() => error);
    }),
  );
};
```

- **Credentials go only to the API's origin.** A token or cookie added to every request
  reaches any third-party URL the app calls.
- **A session cookie from the API** (HttpOnly, Secure, SameSite) is the safer login: script
  cannot read it. If the app must hold an access token, keep it in memory, never in
  `localStorage`, where any injected script can read it. With an API on another origin,
  the API allows this app's origin with credentials in its CORS policy.
- **Errors are rethrown,** so the component shows its own message. An interceptor that
  returns `EMPTY` or a default value hides the failure from the page and the tests.
- `inject()` works only in the interceptor's body, not inside `catchError`; take what you
  need first, as above.

## 6. Tests, lint, and the build

**Tests** run with Vitest through `ng test` (the `@angular/build:unit-test` builder) in
Node with jsdom; there is no browser to install in CI.

```ts
// src/app/orders/order-page.spec.ts
import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { APP_CONFIG } from '../config';
import { OrderPage } from './order-page';

describe('OrderPage', () => {
  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: APP_CONFIG, useValue: { apiUrl: 'https://api.test', environment: 'test' } },
      ],
    });
  });

  afterEach(() => TestBed.inject(HttpTestingController).verify());

  it('shows the order from the API', async () => {
    const fixture = TestBed.createComponent(OrderPage);
    fixture.componentRef.setInput('id', '1');
    TestBed.tick();
    TestBed.inject(HttpTestingController)
      .expectOne('https://api.test/orders/1')
      .flush({ id: 1, name: 'First order' });
    await fixture.whenStable();
    expect((fixture.nativeElement as HTMLElement).querySelector('h1')?.textContent).toBe('First order');
  });
});
```

- **`TestBed.tick()` before `expectOne`:** the resource sends its request when change
  detection runs. `await fixture.whenStable()` before that would wait for a request that
  nobody answers.
- **Fake timers are Vitest's** (`vi.useFakeTimers()`). `fakeAsync` needs `zone.js`, which
  the app does not have.
- **Worth a test each:** `parseConfig` with a missing key, each component's success and
  error state, each interceptor (credentials for the API only, the 401 redirect), and
  each guard.
- The CI configuration of the test target writes a JUnit report for the merge request:

```json
// angular.json, projects.orders-web.architect.test
"configurations": {
  "ci": { "watch": false, "reporters": ["default", "junit"], "outputFile": "test-results/junit.xml" }
}
```

**Lint:** `npx ng lint`, with the config `ng add angular-eslint` writes. It includes the
template accessibility rules: keep them on, and fix what they find (labels, alt text,
keyboard handlers next to click handlers).

**Build:** `npx ng build` builds the `production` configuration. The output in
`dist/orders-web/browser/` is the artifact: `index.html`, scripts and styles whose names
carry a content hash, and the files from `public/`.

- **Budgets** stop the build when the first load grows past 1 MB (a warning from 500 kB)
  or one component's styles past 8 kB. Do not raise a budget to pass; make the feature
  a lazy route or drop the heavy package.
- **No source maps in the deployed files.** Production builds have none by default. If an
  error tracker needs them, build them `hidden` and upload them from the build job.

## 7. Deploy as static files

Every host does three things for the app:

- **Deep links work:** a path that is not a file (`/orders/1`) returns `index.html`, so a
  reload or a shared link opens the app. A missing script or style returns 404, not
  `index.html`, or the browser reports a MIME type error instead of the real problem.
- **Caching:** `index.html` and `config.json` with `Cache-Control: no-cache`, so a deploy
  shows at the next load. Hashed files can be kept for a year: a new build has new names.
- **`config.json` comes from the host,** and the deploy never overwrites or deletes it.

### IIS

`public/web.config` ships with the build. It needs the **URL Rewrite module** on the host.

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <!-- Deep links get the app. Files that exist are served as they are, and a
             missing script, style, or config.json stays a 404. -->
        <rule name="Angular routes" stopProcessing="true">
          <match url=".*" />
          <conditions logicalGrouping="MatchAll">
            <add input="{REQUEST_FILENAME}" matchType="IsFile" negate="true" />
            <add input="{REQUEST_FILENAME}" matchType="IsDirectory" negate="true" />
            <add input="{URL}" pattern="\.(js|css|map|json)$" negate="true" />
          </conditions>
          <action type="Rewrite" url="/index.html" />
        </rule>
      </rules>
    </rewrite>
    <staticContent>
      <!-- Browsers check every file again, so a deploy shows at the next load. -->
      <clientCache cacheControlMode="DisableCache" />
      <remove fileExtension=".json" />
      <mimeMap fileExtension=".json" mimeType="application/json" />
    </staticContent>
  </system.webServer>
</configuration>
```

- IIS gets `no-cache` on every file, the hashed ones included. Browsers then ask again
  and get a short 304; that keeps the config to one rule.
- The deploy syncs the folder with msdeploy (`gitlab-ci`, section 5), plus
  `-skip:objectName=filePath,absolutePath=\\config\.json$`, so the sync does not delete
  the host's `config.json`.
- The site needs no .NET: its application pool runs with No Managed Code.

### Linux with nginx

The deploy copies the files to `/opt/orders-web/releases/<sha>` and points `current` at
them, like the .NET deploy, but restarts nothing: nginx serves the new folder at once.
Ansible writes the site and `/etc/orders-web/config.json`.

```nginx
# deploy/nginx.conf
server {
    listen 80;
    server_name orders.example.com;
    root /opt/orders-web/current;

    location / {
        try_files $uri /index.html;
        add_header Cache-Control "no-cache";
    }

    # Names with a content hash never change.
    location ~ "-[A-Z0-9]{8}\.(?:js|css|woff2?|ttf|svg|png|jpe?g|gif|webp|avif)$" {
        try_files $uri =404;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    # A missing script is a 404, not the app.
    location ~ \.(?:js|css|map)$ {
        try_files $uri =404;
    }

    location = /config.json {
        alias /etc/orders-web/config.json;
        add_header Cache-Control "no-cache";
    }
}
```

- TLS and the `/api` proxy, if the API shares the host name, go in the same server block;
  Ansible owns them (`ansible` skill).
- An `add_header` in a `location` drops every `add_header` from the `server` level. Put
  shared headers in each location, or in a snippet each one includes.

### Docker

```dockerfile
FROM node:24.22.3-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npx ng build

FROM nginxinc/nginx-unprivileged:1.30.6-alpine
COPY deploy/nginx-docker.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/dist/orders-web/browser /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/"]
```

- `deploy/nginx-docker.conf` is the server block above with `listen 8080;` and
  `root /usr/share/nginx/html;`, and the same `alias /etc/orders-web/config.json`.
- **Non-root:** `nginx-unprivileged` runs as user 101 and listens on 8080. The app's files
  are owned by root, so nginx cannot change them.
- The compose file mounts the host's file:
  `./config.json:/etc/orders-web/config.json:ro`, with mode 0644 so user 101 can read it
  (it holds nothing secret). Never `COPY` a `config.json` into the image.
- `.dockerignore` keeps `node_modules/`, `dist/`, `.angular/`, and `.git` out of the build.
- The compose file that runs the image is in `docker` (section 4); `docker-review` checks
  both.

### In the pipeline

The jobs live in `ci-templates` (`gitlab-ci` skill), with the shape of the .NET ones:

- **Image** `node:24.22.3` on the `docker` runner; `npm ci` with `npm_config_cache` inside
  the project, cached on `package-lock.json`.
- **Test job:** `npx ng lint` and `npx ng test --configuration ci`, with the JUnit report as
  an artifact `when: always`.
- **Build job:** `npx ng build`, then `mv dist/orders-web/browser publish`, so the deploy
  jobs ship `publish/` as they do for .NET. Artifact for 90 days, for rollbacks.
- **Deploy jobs:** on Linux, no service restart; on IIS, the `-skip` rule for
  `config.json`; the health check fetches `/` and `/config.json` with `curl --fail`,
  because a static site has no `/health`.

## Before calling it done

```
npm ci
npx ng lint
npx ng test --watch=false
npx ng build
docker build -t orders-web .          # Docker path only
```

- `dist/orders-web/browser/` has no `config.json`, and `grep -rn environment src/` finds
  no environment files.
- The build passes its budgets with no warnings.
- Served with a `config.json` (the image:
  `docker run --rm -p 8080:8080 -v "$PWD/public/config.json:/etc/orders-web/config.json:ro" orders-web`):
  `curl -I localhost:8080/orders/1` gives 200 with `no-cache`, a missing `.js` gives 404,
  and without the mount the page says it could not start.

Then run the `angular-reviewer` agent on the change (in Codex, the `angular-review` skill).
