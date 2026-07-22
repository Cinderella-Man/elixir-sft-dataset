Write me a set of Elixir modules that implement a **role-scoped** nested resource endpoint for team membership, using only `Plug` and standard OTP (no Phoenix, no database, no external dependencies beyond `plug` and `jason`).

Unlike a flat membership model, every membership now carries a **role** — one of `"owner"`, `"admin"`, or `"member"`. Read access is open to any member, but mutating the roster (adding or removing members) is restricted to privileged roles, and owners are protected from being removed by mere admins.

I need these modules:

**`TeamStore`** — a GenServer holding all state in memory (users, teams, and role-tagged memberships). Public functions:

- `TeamStore.start_link(opts)` — starts the process. Accepts a `:name` option.
- `TeamStore.create_user(server, id, token)` — stores a user with a bearer token. Returns `:ok`.
- `TeamStore.create_team(server, team_id)` — creates a team. Returns `:ok`.
- `TeamStore.add_member(server, team_id, user_id, role)` — seeds a membership with a role. Returns `:ok`.
- `TeamStore.get_user_by_token(server, token)` — returns `{:ok, user_id}` or `:error`.
- `TeamStore.team_exists?(server, team_id)` — returns `true`/`false`.
- `TeamStore.is_member?(server, team_id, user_id)` — returns `true`/`false`.
- `TeamStore.role_of(server, team_id, user_id)` — returns `{:ok, role}` or `:error`.
- `TeamStore.list_members(server, team_id)` — returns `{:ok, [%{user_id: id, role: role}]}` or `{:error, :not_found}`.
- `TeamStore.add_member_safe(server, team_id, user_id, role)` — adds a member with a role if the team exists and the user isn't already on the team. Returns `{:ok, user_id}`, `{:error, :not_found}`, or `{:error, :conflict}`.
- `TeamStore.remove_member_safe(server, team_id, user_id)` — removes a member. Returns `{:ok, user_id}`, `{:error, :not_found}` (no team), or `{:error, :not_member}`.

**`AuthPlug`** — reads the `authorization` header, expects `Bearer <token>`, looks the user up via `TeamStore.get_user_by_token/2`, and assigns `:current_user`. On missing/invalid token, halts with 401 JSON `{"error": "unauthorized"}`. Accepts a `:store` option at init.

**`TeamRouter`** — a `Plug.Router` accepting a `:store` option, plugging `AuthPlug` before matching. Endpoints:

- `GET /api/teams/:team_id/members` — 404 `{"error":"not_found"}` if the team is missing; 403 `{"error":"forbidden"}` if the caller isn't a member; otherwise 200 `{"members": [{"user_id": ..., "role": ...}]}`.

- `POST /api/teams/:team_id/members` — body `{"user_id": "...", "role": "..."}` (role optional, defaults to `"member"`, must be one of the three valid roles or the response is 400 `{"error":"bad_request"}`). 404 if the team is missing. If the caller is **not** an `owner` or `admin` of the team (including non-members), 403 `{"error":"forbidden"}`. 409 `{"error":"conflict"}` if the target is already a member. On success 201 `{"added": user_id, "role": role}`.

- `DELETE /api/teams/:team_id/members/:user_id` — 404 if the team is missing. If the caller isn't an `owner`/`admin`, 403. If the target isn't a member, 404 `{"error":"not_found"}`. An `admin` may **not** remove an `owner` (403); only an `owner` may remove an `owner`. On success 200 `{"removed": user_id}`.

All responses must be `application/json`. Give me all modules in a single file, using only `plug`, `jason`, and the OTP standard library.