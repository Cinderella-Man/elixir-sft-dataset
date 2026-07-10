Write me a set of Elixir modules that implement **nested resource endpoints for team membership with optimistic concurrency control**, using only `Plug` and standard OTP (no Phoenix, no database, no external dependencies beyond `plug` and `jason`).

Every team carries a monotonically increasing **version** number. Mutations must present the version they expect to update via an `If-Match` request header; if the version has moved on, the write is rejected. This lets concurrent clients detect lost updates.

I need these modules:

**`TeamStore`** — a GenServer that holds all application state in memory (users, teams, memberships, and per-team version numbers). It should support these public functions:

- `TeamStore.start_link(opts)` — starts the process. Accepts a `:name` option for registration.
- `TeamStore.create_user(server, id, token)` — stores a user with the given ID and bearer token. Returns `:ok`.
- `TeamStore.create_team(server, team_id)` — creates a team with an empty member list and **version `0`**. Returns `:ok`.
- `TeamStore.add_member(server, team_id, user_id)` — adds a user to a team directly (for seeding). Adding a not-yet-present user **increments the team's version by 1**; adding a user already on the team is a no-op that leaves the version unchanged. Returns `:ok`.
- `TeamStore.get_user_by_token(server, token)` — returns `{:ok, user_id}` or `:error`.
- `TeamStore.team_exists?(server, team_id)` — returns `true` or `false`.
- `TeamStore.is_member?(server, team_id, user_id)` — returns `true` or `false`.
- `TeamStore.get_version(server, team_id)` — returns `{:ok, version}` or `{:error, :not_found}`.
- `TeamStore.list_members(server, team_id)` — returns `{:ok, list_of_user_ids}` or `{:error, :not_found}`.
- `TeamStore.add_member_safe(server, team_id, user_id, expected_version)` — atomically adds a member only if all of the following hold. Checks are performed in this order:
  1. If the team does not exist, returns `{:error, :not_found}`.
  2. If `expected_version` does not equal the team's current version, returns `{:error, :stale}`.
  3. If the user is already a member, returns `{:error, :conflict}`.
  4. Otherwise it appends the user, increments the version by 1, and returns `{:ok, user_id, new_version}`.

**`AuthPlug`** — a Plug that reads the `authorization` header, expects `Bearer <token>`, looks the user up via `TeamStore.get_user_by_token/2`, and assigns `:current_user` to the conn. If the token is missing or invalid, it halts the connection with a 401 JSON response `{"error": "unauthorized"}`. It should accept a `:store` option at init time to know which TeamStore process to call.

**`TeamRouter`** — a `Plug.Router` that serves the following endpoints. It should accept a `:store` option and plug `AuthPlug` before route matching.

- `GET /api/teams/:team_id/members` — If the team doesn't exist, return 404 `{"error": "not_found"}`. If the current user is not a member of the team, return 403 `{"error": "forbidden"}`. Otherwise return 200 `{"members": [list_of_user_ids], "version": version}` and set a response header `ETag` whose value is the version rendered as a string (e.g. version `2` → `ETag: 2`).

- `POST /api/teams/:team_id/members` — Reads a JSON body with `{"user_id": "..."}`. The response is decided in this order:
  1. If the team doesn't exist, return 404 `{"error": "not_found"}`.
  2. If the current user is not a member of the team, return 403 `{"error": "forbidden"}`.
  3. If there is no `If-Match` request header, return 428 `{"error": "precondition_required"}`.
  4. If the body is missing a string `"user_id"` field, return 400 `{"error": "bad_request"}`.
  5. Interpret the `If-Match` header value as the expected version (an integer; a non-integer value is treated as a version that can never match). Call `add_member_safe/4` with it. Map its result: `{:error, :stale}` → 412 `{"error": "precondition_failed"}`; `{:error, :conflict}` → 409 `{"error": "conflict"}`; `{:error, :not_found}` → 404 `{"error": "not_found"}`; `{:ok, user_id, new_version}` → 201 `{"added": user_id, "version": new_version}` with a response header `ETag` equal to the new version rendered as a string.

Because every successful write bumps the version, a client that reads the version, then performs a write, invalidates any other client still holding the old version — a second write presenting the now-stale version gets 412.

All error and success responses must be `application/json`. Give me all modules in a single file. Use only `plug`, `jason`, and the OTP standard library.