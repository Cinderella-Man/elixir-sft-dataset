Write me a set of Elixir modules that implement nested resource endpoints for team membership, using only `Plug` and standard OTP (no Phoenix, no database, no external dependencies beyond `plug` and `jason`).

I need these modules:

**`TeamStore`** — a GenServer that holds all application state in memory (users, teams, and memberships). It should support these public functions:

- `TeamStore.start_link(opts)` — starts the process. Accepts a `:name` option for registration.
- `TeamStore.create_user(server, id, token)` — stores a user with the given ID and bearer token. Returns `:ok`.
- `TeamStore.create_team(server, team_id)` — creates a team. Returns `:ok`.
- `TeamStore.add_member(server, team_id, user_id)` — adds a user to a team directly (for seeding). Returns `:ok`.
- `TeamStore.get_user_by_token(server, token)` — returns `{:ok, user_id}` or `:error`.
- `TeamStore.team_exists?(server, team_id)` — returns `true` or `false`.
- `TeamStore.is_member?(server, team_id, user_id)` — returns `true` or `false`.
- `TeamStore.list_members(server, team_id)` — returns `{:ok, list_of_user_ids}` or `{:error, :not_found}`.
- `TeamStore.add_member_safe(server, team_id, user_id)` — adds a member if the team exists and the user is not already on the team. Returns `{:ok, user_id}`, `{:error, :not_found}` if team doesn't exist, or `{:error, :conflict}` if user is already a member.

**`AuthPlug`** — a Plug that reads the `authorization` header, expects `Bearer <token>`, looks the user up via `TeamStore.get_user_by_token/2`, and assigns `:current_user` to the conn. If the token is missing or invalid, it halts the connection with a 401 JSON response `{"error": "unauthorized"}`. It should accept a `:store` option at init time to know which TeamStore process to call.

**`TeamRouter`** — a `Plug.Router` that serves the following endpoints. It should accept a `:store` option and plug `AuthPlug` before route matching.

- `GET /api/teams/:team_id/members` — If the team doesn't exist, return 404 `{"error": "not_found"}`. If the current user is not a member of the team, return 403 `{"error": "forbidden"}`. Otherwise return 200 `{"members": [list_of_user_ids]}`.

- `POST /api/teams/:team_id/members` — Reads a JSON body with `{"user_id": "..."}`. Same 404/403 rules apply. If the user being added is already a member, return 409 `{"error": "conflict"}`. On success, return 201 `{"added": user_id}`.

All error and success responses must be `application/json`. Give me all modules in a single file. Use only `plug`, `jason`, and the OTP standard library.