Write me a set of Elixir modules that implement a nested team-membership endpoint guarded by **optimistic concurrency control** using HTTP `ETag` / `If-Match` semantics, with only `Plug` and standard OTP (no Phoenix, no database, no external dependencies beyond `plug` and `jason`).

Every team's membership roster carries a monotonically increasing **version** number. Reads expose that version as an `ETag`. Writes must present the version they expect via `If-Match`; stale or missing preconditions are rejected so two clients editing the same roster can't silently clobber each other.

I need these modules:

**`TeamStore`** — a GenServer holding users, teams, memberships, and per-team version numbers. Public functions:

- `TeamStore.start_link(opts)` — starts the process. Accepts a `:name` option.
- `TeamStore.create_user(server, id, token)` — stores a user with a bearer token. Returns `:ok`.
- `TeamStore.create_team(server, team_id)` — creates a team at version `0`. Returns `:ok`.
- `TeamStore.add_member(server, team_id, user_id)` — seeds a membership and bumps the version. Returns `:ok`.
- `TeamStore.get_user_by_token(server, token)` — returns `{:ok, user_id}` or `:error`.
- `TeamStore.team_exists?(server, team_id)` — returns `true`/`false`.
- `TeamStore.is_member?(server, team_id, user_id)` — returns `true`/`false`.
- `TeamStore.version(server, team_id)` — returns `{:ok, version}` or `:error`.
- `TeamStore.list_members(server, team_id)` — returns `{:ok, members, version}` or `{:error, :not_found}`.
- `TeamStore.add_member_safe(server, team_id, user_id, expected_version)` — checks the precondition first: returns `{:error, :version_mismatch, current_version}` if `expected_version` doesn't equal the team's current version; then `{:error, :conflict}` if the user is already a member; on success bumps the version and returns `{:ok, user_id, new_version}`; `{:error, :not_found}` if the team is missing.

**`AuthPlug`** — reads `authorization: Bearer <token>`, resolves the user via `TeamStore.get_user_by_token/2`, assigns `:current_user`, and halts with 401 JSON `{"error":"unauthorized"}` otherwise. Accepts a `:store` option.

**`TeamRouter`** — a `Plug.Router` accepting a `:store` option and plugging `AuthPlug` before matching. Endpoints:

- `GET /api/teams/:team_id/members` — 404 `{"error":"not_found"}` if the team is missing; 403 `{"error":"forbidden"}` if the caller isn't a member; otherwise 200 with an `ETag` response header set to the quoted version (e.g. `"3"`) and body `{"members": [...], "version": v}`.

- `POST /api/teams/:team_id/members` — body `{"user_id": "..."}`. Check order: 404 (missing team) → 403 (non-member) → then the precondition. If there is **no** `If-Match` header, return 428 `{"error":"precondition_required"}`. If `If-Match` is present but doesn't match the current version (or isn't a valid version), return 412 `{"error":"precondition_failed"}`. A malformed body is 400 `{"error":"bad_request"}`. If the target is already a member, 409 `{"error":"conflict"}`. On success 201 with an updated `ETag` header and body `{"added": user_id, "version": new_version}`.

`If-Match` values may be quoted (`"3"`) or bare (`3`). All responses must be `application/json`. Give me all modules in a single file, using only `plug`, `jason`, and the OTP standard library.