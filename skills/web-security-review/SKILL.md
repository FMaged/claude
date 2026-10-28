---
name: web-security-review
description: Use when reviewing a web application, or any part of one, for security — a route or handler, login and sessions, an API, a file upload, a template, a CORS or proxy config, or a whole repo (e.g. "is this secure?", "security review this app", "can a user see someone else's data?", "check this endpoint", "audit the login flow"). Reports who can do what they should not — read another user's data, act as someone else, run code on the server — with the file, the line, and the request that proves it.
---

# Web Security Review

Review a web app for what an attacker can do with it. Report problems. Do not rewrite unless
asked.

This is the reading pass for the whole app or the part you were pointed at. For the SQL
itself use `sql-review`; for the image and compose file, `docker-review`; for frontend code
quality beyond security, `frontend-code-review`. If the project has its own invariants skill,
use it as well.

## 0. Map the attack surface first

Before reading any one handler, write down:

- **Every way in**: routes, API endpoints, GraphQL resolvers, websockets, webhooks, uploads,
  OAuth callbacks, admin panels, background jobs that consume user-supplied data, and
  anything the reverse proxy forwards.
- **Who can reach each one**: anonymous, any signed-in user, a role, another service. Read
  the router and the proxy config — the answer is there, not in the handler names.
- **Where auth is enforced**: middleware on a router group, a decorator per handler, a check
  inside the handler, or a gateway in front. A route mounted outside the protected group is
  the most common hole in an app.
- **Trust boundaries**: which data comes from the client, a header, a file, or a third-party
  API, and where the code later treats it as trusted.

Then work from each source of attacker input to each sink it reaches. A finding needs both
ends.

## 1. Can they touch someone else's data (authorization)

The most common serious web bug, and the one scanners do not find. Check it first.

- **An object loaded by id with no ownership check.** `GET /api/invoices/:id` that runs
  `WHERE id = $1` and never compares the owner or tenant. Try every route that takes an id,
  including nested ones — `/orgs/:org/projects/:id` where `:id` is never checked against
  `:org`.
- **The check only in the UI.** A hidden button or a disabled field is not a control; the
  endpoint behind it must refuse.
- **Checked on read but not on write**, or on `GET` but not on `PUT`, `PATCH`, `DELETE`, the
  export, or the bulk endpoint.
- **Mass assignment.** The request body bound straight onto the model, so a client can set
  `role`, `is_admin`, `owner_id`, `tenant_id`, `price`, `verified`. Look for
  `Object.assign(user, req.body)`, `Model(**request.json)`, `update(req.body)`, or
  `Deserialize` derived on the database row type.
- **Tenant scoping left to each query** rather than enforced in one place, so the one query
  that forgets it leaks every tenant.
- **Values the server should own taken from the client**: a price, a total, a user id, a
  discount, a "paid" flag, a role.
- **An admin route any signed-in user can call**, because the admin check lives in the
  frontend router.

## 2. Are they who they say (authentication and sessions)

- Passwords hashed with anything but a slow salted hash (argon2id, bcrypt, scrypt). A fast
  hash — MD5, SHA-anything — is a finding even when salted.
- Secrets, tokens, or HMACs compared with `==` instead of a constant-time compare.
- Session ids or reset tokens from a non-cryptographic source: `Math.random`, `rand()`,
  `random.random`, a timestamp, an incrementing id.
- Session not rotated on login (fixation), or not invalidated on logout and password change.
- **JWT**: `alg: none` accepted, the algorithm taken from the token header, `decode` used
  where `verify` was meant, no `exp`, no audience or issuer check, or a long-lived token with
  no way to revoke it.
- **Password reset**: token not single-use, not expiring, not bound to the user, or the link
  built from the request's `Host` header — the attacker sets `Host` and the victim's token
  is mailed pointing at the attacker's domain.
- Login, reset, and OTP endpoints with no rate limit or lockout.
- Different responses or timing for "no such user" and "wrong password", where account
  enumeration matters.
- **OAuth / OIDC**: no `state` check, a redirect URI matched by prefix, or the provider's
  email trusted without `email_verified`.
- Session cookie without `HttpOnly`, `Secure`, and `SameSite`, or with a `Domain` broader
  than the app.
- MFA skipped by requesting the post-login URL directly.

## 3. Can they run something (injection)

Trace a request field to the sink. A parameterised call is safe; anything assembled from
strings is not, whatever the comment says about where the input comes from.

- **SQL and NoSQL**: string-built queries, an identifier from input without an allowlist
  (`ORDER BY ${sort}`), Mongo operator injection (`{"$ne": null}` where a string was
  expected). Hand the details to `sql-review`.
- **OS command**: `exec`, `system`, `subprocess(..., shell=True)`, `child_process.exec`,
  `sh -c` with any input. Also argument injection — a value starting with `-` passed to
  `git`, `tar`, `curl`, or `ffmpeg`.
- **Template (SSTI) and eval**: user input used as the template rather than a variable in it
  — `render_template_string(input)`, a template compiled from a field users can edit,
  `eval`, `new Function`.
- **Path traversal**: a path from input joined onto a base directory without resolving it
  and checking it is still under the base. Covers `../`, encoded and double-encoded forms,
  and absolute paths — `path.join` and `Path::join` do not protect, and joining an absolute
  path onto a base returns the absolute path.
- **Deserialization**: `pickle`, `yaml.load` without a safe loader, Java or .NET native
  serialization, PHP `unserialize`, on anything that crosses a trust boundary — a cookie
  included.
- **XML**: a parser with external entities enabled (XXE), on uploads, SAML, SOAP, SVG, or
  Office files.
- **Headers**: input placed in a response header or a `Location` without stripping `\r\n`.
- **Regex DoS**: a user-supplied regex, or a nested-quantifier pattern like `(a+)+` run on
  user input in a backtracking engine.

## 4. Can they run script in someone else's browser (XSS)

- **Raw-HTML sinks** fed anything user-influenced: `innerHTML`, `outerHTML`,
  `insertAdjacentHTML`, `document.write`, `dangerouslySetInnerHTML`, `v-html`, `{@html}`,
  `[innerHTML]`, `|safe`, `mark_safe`, `{{{ }}}`, `<%-`, `Html.Raw`. The framework escapes by
  default; each of these turns it off.
- User-supplied URLs in `href`, `src`, `action`, or `window.location` with no scheme
  allowlist. `javascript:` and `data:` run script.
- Markdown or rich text rendered to HTML without a sanitiser (DOMPurify, ammonia, bleach),
  or sanitised and then changed afterwards.
- JSON embedded in a `<script>` tag without escaping `</script>` and `<!--`.
- **DOM XSS**: `location.hash`, `location.search`, `document.referrer`, or `postMessage` data
  flowing into a sink.
- `postMessage` handlers that do not check `event.origin`, or that post sensitive data to
  `*`.
- Uploaded HTML or SVG served from the app's own origin with a type the browser renders.
- **CSP** absent, or with `unsafe-inline`, `unsafe-eval`, or a wildcard source that makes it
  decorative. CSP is a backstop: report the sink first and the missing CSP after.

## 5. Can they make the server send requests (SSRF and redirects)

- **Any server-side fetch of a user-supplied URL**: link previews, webhooks, image import,
  PDF rendering, "import from URL", OIDC discovery. Check the server cannot reach
  `127.0.0.1`, `[::1]`, `169.254.169.254` (cloud metadata), private ranges, or internal
  service names — including through a redirect the client follows, an alternative IP
  encoding (`2130706433`, `0x7f.1`), or a DNS name that resolves differently at fetch time
  than at check time.
- A headless browser or document converter given user HTML. It fetches whatever the HTML
  asks for, `file://` included.
- **Open redirect**: `?next=` or `?return_to=` sent to `Location` without checking it is a
  path on this site. `//evil.example` and `/\evil.example` are not relative paths. It is
  serious inside a login or OAuth flow, where it carries tokens off-site.

## 6. Can another site act as them (CSRF, CORS, framing)

- A cookie-authenticated state change with no CSRF token and no `SameSite=Lax` or `Strict`.
  A state change on `GET` is CSRF-able even with `Lax`.
- A JSON endpoint that also accepts `text/plain` or form bodies, which a cross-site form can
  send without a preflight.
- **CORS**: the request's `Origin` reflected into `Access-Control-Allow-Origin` along with
  `Allow-Credentials: true`; `null` allowed; an origin matched with `endsWith` or an
  unanchored regex, so `evil-example.com` passes a check meant for `example.com`.
- No `frame-ancestors` (or `X-Frame-Options`) on a page with one-click actions.
- A websocket upgrade that authenticates by cookie and does not check `Origin`.

## 7. Files

- Upload type decided by the extension or the client's `Content-Type` rather than the
  content, and then served back with a type the browser will render.
- Uploads stored under the web root, or under a filename the client chose.
- No size limit, or one checked only after the whole body is buffered.
- Archives extracted without checking each entry's path (zip slip) or the total expanded
  size (zip bomb).
- Uploads handed to ImageMagick, Ghostscript, LibreOffice, or ffmpeg with no policy
  restricting the formats they accept.
- User content served without `Content-Disposition: attachment` and
  `X-Content-Type-Options: nosniff`.

## 8. What leaks

- **Secrets committed** — keys, tokens, `.env`, private keys, connection strings — in the
  tree or anywhere in git history.
- **Secrets shipped to the browser**: anything under `NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`,
  a server key that ended up in the bundle, or source maps published to production.
- **API responses that serialise the whole row**: password hash, reset token, internal
  flags, other users' emails. Look for `return user`, `res.json(model)`, or `Serialize`
  derived on the database type.
- Stack traces, SQL errors, or framework debug pages returned to the client.
- Tokens, passwords, or personal data written to logs — often through a logged request
  body or a URL with a token in the query string.
- `.git/`, backup files, directory listings, `/actuator`, `/debug`, `/metrics`, Swagger, or
  GraphQL introspection reachable from the internet without anyone deciding it should be.
- Tokens in URLs, which end up in logs, browser history, and `Referer`.

## 9. Abuse, races, and limits

- No rate limit on anything that costs money or sends mail or SMS: signup, reset, OTP, a
  model call, an export.
- No cap on page size, body size, batch size, or GraphQL query depth.
- **Check-then-act races**: a coupon used twice, a balance overdrawn, an invite accepted
  twice — two concurrent requests both pass the check. Look for a read, a check, and a
  write with no lock, no unique constraint, and no atomic update.
- Negative or huge numbers where only small positive ones make sense — quantity `-1`, amount
  `1e308`.
- A multi-step flow whose later steps do not re-check what the earlier ones did, so a
  client can jump from step 1 to step 3.

## 10. Proxy, transport, and headers

- `X-Forwarded-For`, `X-Real-IP`, or `X-Forwarded-Proto` trusted from any client rather than
  only from the proxy — then used for rate limiting, an audit log, or an IP allowlist.
- The `Host` header trusted to build absolute URLs, redirects, or cache keys.
- The app's own port reachable from outside alongside the proxy, so the proxy's auth and
  headers can be skipped by going straight to it.
- No HTTPS redirect or no `Strict-Transport-Security` on a site that sets cookies.
- TLS verification turned off in an outbound client: `verify=False`,
  `rejectUnauthorized: false`, `danger_accept_invalid_certs`.
- Missing `nosniff`, `Referrer-Policy`, or `frame-ancestors`. Should-fix, not blockers,
  unless a finding above depends on them.

## 11. Dependencies and config

- A dependency with a known advisory. Say whether the app reaches the vulnerable function;
  an advisory on a path the app never calls is a nit.
- No lockfile, or one not committed.
- Default credentials, a placeholder secret key (`changeme`, `secret`, the framework's
  example), or one signing key shared between environments.
- An admin interface, database console, or debug tool enabled in the production config.

## Commands

Run probes only against a local or staging instance the user owns. Never point them at
production or at anyone else's system without written permission.

```
gitleaks detect --source . -v                  # secrets in the tree and in history
semgrep --config p/owasp-top-ten --config p/secrets .
npm audit --omit=dev                           # or pip-audit, cargo audit, govulncheck ./...

# the sinks, to start each source-to-sink trace
rg -n 'innerHTML|dangerouslySetInnerHTML|v-html|\|safe|mark_safe|document\.write'
rg -n 'exec\(|execSync|spawn\(|system\(|shell=True|Command::new|eval\(|new Function'
rg -n 'pickle\.load|yaml\.load\(|unserialize|readObject'
rg -n 'verify=False|rejectUnauthorized|danger_accept_invalid'

# authorization: user B asking for user A's object
curl -si -H "Cookie: session=$B_SESSION" http://localhost:8080/api/orders/$A_ORDER_ID

# CORS: does it reflect an arbitrary origin with credentials
curl -si -H 'Origin: https://evil.example' http://localhost:8080/api/me | grep -i '^access-control'

# security headers and cookie flags
curl -si http://localhost:8080/ | grep -iE '^(strict-transport|content-security|x-content-type|x-frame|referrer-policy|set-cookie)'
```

A scanner hit is a lead, not a finding. Trace it to input an attacker controls before
reporting it, and say so when you could not.

## How to report

Most serious first, as a list:

```
<file>:<line> — <blocker | should fix | nit>: <who> can <what they get>, because <the gap>
Proof: <the request, or the steps, that shows it>
Fix: <the change, one line>
```

"Who" is one of: anyone, any signed-in user, a user in another tenant, an admin, or a victim
who opens a link. It decides severity more than the bug class does — an IDOR any signed-in
user can reach is a blocker; stored XSS that only an admin can plant on their own page is a
nit.

- **blocker**: someone with an account or less can read or change another user's data, act
  as another user, run code on the server, reach internal services, or read a secret.
- **should fix**: needs a victim's click, a particular role, or a second bug to chain; or a
  missing defence — a rate limit, a header, a cookie flag — that makes a later bug worse.
- **nit**: hardening with no current path to harm.

Mark each finding confirmed (traced from input to sink, or reproduced) or unconfirmed (the
sink is there but you could not tell whether input reaches it). Keep unconfirmed ones to one
line each, naming what to check.

Separate "an attacker can do this today" from "a defence in depth is missing". The reader
needs to know which list to clear before shipping.

If the app is fine, say so in one sentence and name what you checked hardest — usually the
routes that take an id, which routes sit outside the auth middleware, and the raw-HTML sinks.
Do not invent findings to fill a list. If you add a comment as part of a fix, follow the
`code-comments` skill.
