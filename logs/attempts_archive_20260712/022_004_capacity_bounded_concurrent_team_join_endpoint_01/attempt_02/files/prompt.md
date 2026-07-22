Write me a set of Elixir modules that implement a nested team-membership endpoint with **capacity-bounded self-service enrollment** under concurrent access, using only `Plug` and standard OTP (no Phoenix, no database, no external dependencies beyond `plug` and `jason`).

Each team has a fixed **capacity**. Users enroll themselves ("join") and withdraw ("leave") through the API; because many join requests can arrive simultaneously, capacity must be enforced atomically so a team can never exceed its limit. Serialize all mutations through the GenServer so the check-and-insert is a single atomic step.

I need these modules:

**`TeamStore`** — a GenServer holding users, teams (with capacity), and memberships. Public functions:

- `TeamStore.start_link(opts)` — starts the process. Accepts a `:name` option.
- `TeamStore.create_user(server, id, token)` — stores a user with a bearer token. Returns `:ok`.
- `TeamStore.create_team(server, team_id, capacity)` — creates a team with a maximum size. Returns `:ok`.
- `TeamStore.add_member(server, team_id, user_id)` — seeds a membership directly (no capacity check). Returns `:ok`.
- `TeamStore.get_user_by_token(server, token)` — returns `{:ok, user_id}` or `:error`.
- `TeamStore.team_exists?(server, team_id)` — returns `true`/`false`.
- `TeamStore.is_member?(server, team_id, user_id)` — returns `true`/`false`.
- `TeamStore.capacity(server, team_id)` — returns `{:ok, capacity}` or `:error`.
- `TeamStore.size(server, team_id)` — returns `{:ok, count}` or `:error`.
- `TeamStore.list_members(server, team_id)` — returns `{:ok, members}` or `{:error, :not_found}`.
- `TeamStore.join_safe(server, team_id, user_id)` — atomically enrolls a user: `{:error, :not_found}` if the team is missing, `{:error, :already_member}` if already enrolled, `{:error, :full}` if the team is at capacity, otherwise `{:ok, user_id, new_size}`.
- `TeamStore.leave_safe(server, team_id, user_id)` — `{:error, :not_found}` if the team is missing, `{:error, :not_member}` if not enrolled, otherwise `{:ok, user_id, new_size}`.

**`AuthPlug`** — reads `authorization: Bearer <token>`, resolves the user via `TeamStore.get_user_by_token/2`, assigns `:current_user`, and halts with 401 JSON `{"error":"unauthorized"}` otherwise. Accepts a `:store` option.

**`TeamRouter`** — a `Plug.Router` accepting a `:store` option and plugging `AuthPlug` before matching. Endpoints:

- `GET /api/teams/:team_id/members` — 404 `{"error":"not_found"}` if missing; 403 `{"error":"forbidden"}` if the caller isn't a member; otherwise 200 `{"members": [...], "size": n, "capacity": c}`.

- `POST /api/teams/:team_id/join` — the authenticated caller enrolls **themselves** (no prior membership required). 404 if the team is missing. 409 `{"error":"already_member"}` if already enrolled. 409 `{"error":"team_full"}` if at capacity. On success 201 `{"joined": user_id, "size": n}`.

- `DELETE /api/teams/:team_id/join` — the authenticated caller withdraws themselves. 404 if the team is missing. 409 `{"error":"not_member"}` if not enrolled. On success 200 `{"left": user_id, "size": n}`.

Capacity must hold even when many joins race concurrently. All responses must be `application/json`. Give me all modules in a single file, using only `plug`, `jason`, and the OTP standard library.