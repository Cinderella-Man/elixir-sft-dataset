Write me a set of Elixir modules that implement **invitation-based** nested resource endpoints for team membership, using only `Plug` and standard OTP (no Phoenix, no database, no external dependencies beyond `plug` and `jason`).

Unlike a plain "add member" endpoint, joining a team here is a two-step lifecycle: an existing member *invites* a user (creating a **pending** invitation), and the invited user must *accept* it before they become a member.

I need these modules:

**`TeamStore`** — a GenServer that holds all application state in memory (users, teams, memberships, and pending invitations). It should support these public functions:

- `TeamStore.start_link(opts)` — starts the process. Accepts a `:name` option for registration.
- `TeamStore.create_user(server, id, token)` — stores a user with the given ID and bearer token. Returns `:ok`.
- `TeamStore.create_team(server, team_id)` — creates a team. Returns `:ok`.
- `TeamStore.add_member(server, team_id, user_id)` — adds a user to a team directly (for seeding). Returns `:ok`.
- `TeamStore.get_user_by_token(server, token)` — returns `{:ok, user_id}` or `:error`.
- `TeamStore.team_exists?(server, team_id)` — returns `true` or `false`.
- `TeamStore.is_member?(server, team_id, user_id)` — returns `true` or `false`.
- `TeamStore.list_members(server, team_id)` — returns `{:ok, list_of_user_ids}` or `{:error, :not_found}`.
- `TeamStore.list_invitations(server, team_id)` — returns `{:ok, list_of_pending_user_ids}` or `{:error, :not_found}`.
- `TeamStore.has_pending_invite?(server, team_id, user_id)` — returns `true` or `false`.
- `TeamStore.invite(server, team_id, user_id)` — records a pending invitation. Returns `{:ok, user_id}`, `{:error, :not_found}` if the team doesn't exist, or `{:error, :conflict}` if the user is already a member OR already has a pending invitation.
- `TeamStore.accept_invitation(server, team_id, user_id)` — promotes a pending invitation into full membership (removing the invitation). Returns `{:ok, user_id}`, `{:error, :not_found}` if the team doesn't exist or there is no pending invitation for that user.

**`AuthPlug`** — a Plug that reads the `authorization` header, expects `Bearer <token>`, looks the user up via `TeamStore.get_user_by_token/2`, and assigns `:current_user` to the conn. If the token is missing or invalid, it halts the connection with a 401 JSON response `{"error": "unauthorized"}`. It should accept a `:store` option at init time to know which TeamStore process to call.

**`TeamRouter`** — a `Plug.Router` that serves the following endpoints. It should accept a `:store` option and plug `AuthPlug` before route matching.

- `GET /api/teams/:team_id/members` — If the team doesn't exist, return 404 `{"error": "not_found"}`. If the current user is not a member, return 403 `{"error": "forbidden"}`. Otherwise return 200 `{"members": [list_of_user_ids]}`.

- `GET /api/teams/:team_id/invitations` — Same 404 / 403 rules (must be a member to view). Otherwise return 200 `{"invitations": [list_of_pending_user_ids]}`.

- `POST /api/teams/:team_id/invitations` — Reads a JSON body with `{"user_id": "..."}`. If the team doesn't exist, return 404. If the current user is not a member, return 403 (only members may invite). If the body is malformed / missing `user_id`, return 400 `{"error": "bad_request"}`. If the invited user is already a member or already has a pending invitation, return 409 `{"error": "conflict"}`. On success, return 201 `{"invited": user_id, "status": "pending"}`.

- `POST /api/teams/:team_id/invitations/:user_id/accept` — The invited user accepts their own invitation. If the team doesn't exist, return 404. If the authenticated user is **not** the `:user_id` in the path, return 403 `{"error": "forbidden"}` (you cannot accept someone else's invitation). If there is no pending invitation for that user, return 404 `{"error": "not_found"}`. On success, return 200 `{"joined": user_id}` and the user becomes a full member.

All error and success responses must be `application/json`. Give me all modules in a single file. Use only `plug`, `jason`, and the OTP standard library.