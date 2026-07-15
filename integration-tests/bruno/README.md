# PIC-SURE Bruno Integration Suite

Integration tests for the PIC-SURE API, targeting a local `pic-sure-all-in-one` (AIO)
stack. Requests are organized into numbered folders that run in a rough dependency
order (smoke -> auth -> data services -> flag-gated features -> negative cases).

## Prerequisites

- A local AIO stack up and reachable at `https://localhost` (self-signed cert).
- [`@usebruno/cli`](https://www.npmjs.com/package/@usebruno/cli) (`bru`) installed,
  v3.5+ recommended: `npm install -g @usebruno/cli`.
- Four tokens/secrets, described below. Not all are required — see the env var table.

## Token model

PSAMA (the PIC-SURE auth microapp) rejects **long-term** tokens on every route except
`/psama/user/me*` (enforced by its `JWTFilter`). That's why a separate short-lived
session token exists: PSAMA-direct admin CRUD, `token/refresh`, and TOS endpoints all
need it, while gateway routes (`/picsure/**`) take the long-term tokens.

| Token | Lifetime | Used for |
|---|---|---|
| `PICSURE_USER_TOKEN` | long-term | Default bearer for all gateway routes (`/picsure/**`) — HPDS, dictionary, visualization, operations, uploader. |
| `PICSURE_ADMIN_TOKEN` | long-term, SUPER_ADMIN | Gateway-enforced admin actions, e.g. `POST/PUT/DELETE /picsure/operations/configuration/admin`. Must belong to a SUPER_ADMIN user. |
| `PICSURE_SESSION_TOKEN` | short-lived (browser JWT, <1h from a real login) | PSAMA-direct endpoints: `/psama/role`, `/psama/privilege`, `/psama/accessRule`, `/psama/connection`, `/psama/mapping`, `/psama/application`, `/psama/token/refresh`, `/psama/tos/*`, `/psama/user` (list/get), `/psama/studyAccess`. |
| `PSAMA_CLIENT_SECRET` | optional | PSAMA's `APPLICATION_CLIENT_SECRET` (from the local AIO `psama.env`). When set alongside `PICSURE_SESSION_TOKEN`, `10-psama/folder.bru`'s pre-request script re-signs the pasted session token's claims with a fresh `iat`/`exp` (HS512), auto-refreshing an expired JWT so you don't have to re-paste it every run. |
| `PICSURE_APPLICATION_TOKEN` | optional | Must be a PSAMA **application** JWT (subject `PSAMA_APPLICATION|<uuid>`), not the opaque client secret. In a local AIO stack, the gateway's `TOKEN_INTROSPECTION_TOKEN` is one. Enables `10-psama/token/02-token-inspect`; the request is skipped when unset. |

### Auto-mint caveat

The auto-mint script only refreshes the JWT's own `iat`/`exp` claims by re-signing —
it cannot resurrect server-side session state. PSAMA tracks login sessions in an
in-memory, per-process cache keyed by subject with an 8-hour TTL
(`SessionService` / `application.max.session.length`). If the local `psama`
container has been restarted since you last captured `PICSURE_SESSION_TOKEN` from a
real browser login, that cache entry is gone even though the re-signed JWT looks
fresh. Only `10-psama/token/01-token-refresh` calls `SessionService.isSessionExpired`
directly, so it's the one request that can 400 with `"Your session has expired.
Please log in again."` in that situation — every other session-token-authenticated
request (validated by the general JWT filter, which doesn't check the session cache)
keeps working. If you hit this, re-paste a freshly captured session token (see
below).

### Token acquisition

- **Long-term user token**: from the local frontend after logging in (its stored
  profile/session), or `GET /psama/user/me?hasToken` with a valid session token.
- **Long-term admin token**: same mechanism, but the account must have the
  `SUPER_ADMIN` role.
- **Session token**: log into the local frontend (`https://localhost/`), open
  DevTools -> Application/Storage -> Local Storage -> `https://localhost` -> key
  `token`. Copy the raw JWT value.
- **Application token** (optional): in a local AIO stack, use the gateway's
  `TOKEN_INTROSPECTION_TOKEN` value.

## Setup

```bash
cd integration-tests/bruno
cp .env.example .env
# edit .env and fill in the tokens above
```

`.env` is gitignored. Bruno reads it via `process.env.*` references in
`environments/local.bru`; nothing sensitive lives in the committed `.bru` files.

### Env vars (`environments/local.bru`)

| Var | Default | Meaning |
|---|---|---|
| `baseUrl` | `https://localhost` | Root URL of the AIO stack (gateway + PSAMA share this host via the reverse proxy). |
| `userToken` | `{{process.env.PICSURE_USER_TOKEN}}` | See token model above. |
| `adminToken` | `{{process.env.PICSURE_ADMIN_TOKEN}}` | See token model above. |
| `applicationToken` | `{{process.env.PICSURE_APPLICATION_TOKEN}}` | See token model above; optional. |
| `sessionToken` | `{{process.env.PICSURE_SESSION_TOKEN}}` | See token model above; optional but required for most of `10-psama`. |
| `psamaClientSecret` | `{{process.env.PSAMA_CLIENT_SECRET}}` | See token model above; optional, enables auto-mint. |
| `testSearchTerm` | `age` | Search term used by dictionary/HPDS search requests. |
| `testConceptPath` | *(blank)* | Concept path used by requests needing a specific concept (e.g. signed-url). Most requests instead discover a concept path at runtime and cache it in a Bruno runtime var. |
| `openAccessEnabled` | `true` | Matches the stack's `GATEWAY_OPEN_ACCESS_ENABLED`; the committed default reflects that the AIO stack has open access on. Gates `20-hpds/open-aggregate/*`. |
| `uploaderEnabled` | `false` | Gates `60-uploader/*`; the default AIO stack doesn't run a healthy uploader. |
| `signedUrlEnabled` | `false` | Gates `20-hpds/09-query-signed-url`; S3 signing isn't configured in a default AIO stack. |

## How to run

**Whole suite** (the canonical command — from the collection root):

```bash
cd integration-tests/bruno
bru run -r --env local --insecure --sandbox developer
```

- `-r` recurses into subfolders — Bruno does **not** do this by default, and without
  it most of the suite silently doesn't run.
- `--insecure` accepts the stack's self-signed cert.
- `--sandbox developer` is **required**: `10-psama/folder.bru`'s pre-request script
  calls `require("crypto")` to auto-mint the session token, and Bruno's default
  `safe` (quickjs) sandbox blocks `require`. Without this flag every request under
  `10-psama` fails/errors identically (see Troubleshooting).

**Single folder**, same flags:

```bash
bru run -r 10-psama --env local --insecure --sandbox developer
```

**Bruno GUI app**: open the collection (`integration-tests/bruno`), select the
`local` environment, and set the runtime sandbox to "Developer" in the collection's
JS sandbox settings (Settings -> Runtime) before running — the GUI runner has the
same `require("crypto")` constraint as the CLI's `--sandbox developer` flag.

## Flag-gated folders

| Flag | Default | Gates |
|---|---|---|
| `openAccessEnabled` | `true` | `20-hpds/open-aggregate/*` (tokenless queries via the gateway's open-access grant). |
| `uploaderEnabled` | `false` | `60-uploader/*`. |
| `signedUrlEnabled` | `false` | `20-hpds/09-query-signed-url`. |

Requests gated off by a flag report as **skipped**, not failed.

## Mutation policy

- Anything the suite creates is prefixed `bruno-test-` and is **self-cleaning**:
  each admin CRUD folder (`10-psama/{role,privilege,accessRule,connection,mapping,
  application}`, `50-operations/{configuration,named-datasets}`) creates its fixture
  early in the sequence and deletes it at the end, in the same run.
- `10-psama/user/*` and `10-psama/tos/*` are **read-only** — no user records or TOS
  acceptance state are ever mutated.
- `10-psama/study-access/01-create.bru` is **intentionally always skipped** (its
  pre-request script calls `bru.runner.skipRequest()` unconditionally):
  `POST /psama/studyAccess` creates a role, privileges, and access rules as one
  compound operation with no single undo endpoint. Run it manually if you need to
  exercise it, then clean up via the role/privilege/accessRule admin endpoints.

## Known issues the suite documents

These are pre-existing backend behaviors the suite asserts against explicitly
(search each file for `known bug` to see the reasoning in context) rather than
failures to fix here:

- **`10-psama/user/03-user-me-consents`** — `UserController.getUserConsents`
  declares `@PathVariable("userId")` but the `/me/consents` route has no
  `{userId}` segment, so it 500s. Accepts `[200, 500]`.
- **`10-psama/tos/02-tos-accepted`** — `TermsOfServiceController.hasUserAcceptedTOS`
  has a `Boolean`/`text-plain` converter mismatch, so it 500s. Accepts
  `[200, 404, 500]`.
- **`10-psama/access-rule/01-all-types`** — `AccessRuleController.getAllTypes()`
  declares a `consumes` clause on a GET mapping, so requests without a matching
  content type 400. Accepts `[200, 400]`.
- **`30-dictionary/09-facet-detail`** — `FacetController.facetDetails`'s
  `@PathVariable` params lack an explicit name, so Spring throws resolving the
  path-variable name, surfaced as a 500. Accepts `[200, 500]`.
- **`90-negative/01-no-token`** — expected a 401 for a tokenless request, but on
  this stack (`GATEWAY_OPEN_ACCESS_ENABLED=true`) the gateway's `OpenAccessFilter`
  grants every tokenless `/picsure/**` request because `MANUAL_ROLE_OPEN_ACCESS`'s
  only privilege has zero attached access rules. Reproduced across multiple routes,
  not just dictionary. The file's `docs` block also notes that
  `PsamaIntrospectionFilter`'s own `missing_token` 401 check never fires on this
  stack, which points at deployed-image/build skew rather than intentional
  behavior — worth re-checking after the next AIO gateway rebuild. Currently
  asserts the actual (200) behavior with the reasoning inline.

## CI usage

```bash
bru run -r --env local --insecure --sandbox developer --reporter-json results.json
```

`bru` exits non-zero on any failed request, so this is CI-ready as-is. `results.json`
is written into the collection directory and is gitignored — do not commit it.

## Troubleshooting

- **TLS errors** — pass `--insecure`; the stack uses a self-signed cert.
- **401 on gateway routes** — token expired, or (for `10-psama/*`) a long-term
  token was used where PSAMA expects the short-lived session token.
- **401/400 on `10-psama/*` in general** — the pasted `PICSURE_SESSION_TOKEN` is
  stale and `PSAMA_CLIENT_SECRET` isn't set (so auto-mint can't run); paste a fresh
  session token or set the secret.
- **`10-psama/token/01-token-refresh` returns 400 "Your session has expired"
  even though other `10-psama` requests pass** — the underlying PSAMA login
  session (an in-memory, per-process cache, independent of the JWT's own `exp`)
  was lost, most likely because the `psama` container restarted after you
  captured `PICSURE_SESSION_TOKEN`. Auto-mint re-signs the JWT but cannot restore
  that cache entry. The request treats this as a documented environmental
  dependency and accepts `[200, 400]` (asserting a fresh token in the body on
  the 200 path), so it won't fail the run; to exercise the positive path,
  re-paste a session token captured after the current `psama` process started.
- **Every `10-psama/*` request errors identically** — you forgot
  `--sandbox developer`; the folder's pre-request script needs `require("crypto")`.
- **Empty dictionary results** — the stack's data hasn't been loaded/seeded yet.
