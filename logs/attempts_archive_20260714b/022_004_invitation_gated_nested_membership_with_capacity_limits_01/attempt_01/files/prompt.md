Write me a set of Elixir modules that implement **invitation-gated nested resource endpoints for team membership with capacity limits**, using only `Plug` and standard OTP (no Phoenix, no database, no external dependencies beyond `plug` and `jason`).

Membership is a two-step handshake instead of a direct add. An existing active member *invites* a user, which creates a **pending invitation**. The invited user (and only that user) *accepts* their own invitation, which promotes them to an **active member** — but only if the team is not already at capacity. Teams have a fixed maximum number of active members.

I need these modules:

**`TeamStore`** — a GenServer that holds all application state in memory (users, teams, active members, pending invitations, and per-team capacity). It should support these public functions:

- `TeamStore.start_link(opts)` — starts the process. Accepts a `:name` option for registration.
- `TeamStore.create_user(server, id, token)` — stores a user with the given ID and bearer token. Returns `:ok`.
- `TeamStore.create_team(server, team_id, capacity)` — creates a team with an empty active-member list, no invitations, and the given integer `capacity` (maximum number of active members). Returns `:ok`.
- `TeamStore.add_member(server, team_id, user_id)` — adds a user directly to a team's active members (for seeding; ignores capacity). Returns `:ok`.
- `TeamStore.get_user_by_token(server, token)` — returns `{:ok, user_id}` or `:error`.
- `TeamStore.team_exists?(server, team_id)` — returns `true` or `false`.
- `TeamStore.is_member?(server, team_id, user_id)` — returns `true` if the user is an **active** member, else `false`.
- `TeamStore.has_invitation?(server, team_id, user_id)` — returns `true` if the user has a **pending** invitation on the team, else `false`.
- `TeamStore.list_members(server, team_id)` — returns `{:ok, list_of_active_user_ids}` or `{:error, :not_found}`.
- `TeamStore.list_invitations(server, team_id)` — returns `{:ok, list_of_pending_user_ids}` or `{:error, :not_found}`.
- `TeamStore.invite(server, team_id, user_id)` — records a pending invitation. Checks in order: team missing → `{:error, :not_found}`; the user is already an active member → `{:error, :already_member}`; the user already has a pending invitation → `{:error, :already_invited}`; otherwise add the pending invitation and return `{:ok, user_id}`.
- `TeamStore.accept(server, team_id, user_id)` — promotes the user's own pending invitation to active membership. Checks in order: team missing → `{:error, :not_found}`; the user has no pending invitation → `{:error, :no_invitation}`; the team already has `capacity` active members → `{:error, :team_full}`; otherwise move the user from invitations to active members and return `{:ok, team_id}`.

**`AuthPlug`** — a Plug that reads the `authorization` header, expects `Bearer <token>`, looks the user up via `TeamStore.get_user_by_token/2`, and assigns `:current_user` to the conn. If the token is missing or invalid, it halts the connection with a 401 JSON response `{"error": "unauthorized"}`. It should accept a `:store` option at init time to know which TeamStore process to call.

**`TeamRouter`** — a `Plug.Router` that serves the following endpoints. It should accept a `:store` option and plug `AuthPlug` before route matching. Note that the endpoints have **different authorization requirements**: listing and inviting require the caller to be an active member, but accepting is done by the invited (non-member) user.

- `GET /api/teams/:team_id/members` — If the team doesn't exist, return 404 `{"error": "not_found"}`. If the current user is not an active member, return 403 `{"error": "forbidden"}`. Otherwise return 200 `{"members": [list_of_active_user_ids]}`.

- `GET /api/teams/:team_id/invitations` — Same 404/403 rules (caller must be an active member). Otherwise return 200 `{"invitations": [list_of_pending_user_ids]}`.

- `POST /api/teams/:team_id/invitations` — Reads a JSON body with `{"user_id": "..."}`. Decided in order: team missing → 404 `{"error": "not_found"}`; caller is not an active member → 403 `{"error": "forbidden"}`; body missing a string `"user_id"` → 400 `{"error": "bad_request"}`; then call `invite/3` and map its result: `{:error, :already_member}` → 409 `{"error": "already_member"}`; `{:error, :already_invited}` → 409 `{"error": "already_invited"}`; `{:error, :not_found}` → 404 `{"error": "not_found"}`; `{:ok, user_id}` → 201 `{"invited": user_id}`.

- `POST /api/teams/:team_id/members` — This is the **accept** endpoint; the current user accepts their own pending invitation. No request body is required. Decided in order: team missing → 404 `{"error": "not_found"}`; then call `accept/3` for the current user and map its result: `{:error, :no_invitation}` → 403 `{"error": "forbidden"}`; `{:error, :team_full}` → 409 `{"error": "team_full"}`; `{:error, :not_found}` → 404 `{"error": "not_found"}`; `{:ok, team_id}` → 201 `{"joined": team_id}`.

All error and success responses must be `application/json`. Give me all modules in a single file. Use only `plug`, `jason`, and the OTP standard library.