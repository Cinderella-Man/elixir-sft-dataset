Write me a set of Elixir modules that implement **two-level nested** resource endpoints (teams → projects → members) with **cascading authorization**, using only `Plug` and standard OTP (no Phoenix, no database, no external dependencies beyond `plug` and `jason`).

The nesting is deeper than a single membership list: each team owns projects, and each project has its own member roster (a subset of the team's members). Authorization cascades — to see or modify a project's roster you must be a member of the *team* **and** a member of the *project*.

I need these modules:

**`TeamStore`** — a GenServer that holds all application state in memory (users, teams, team memberships, projects, and project memberships). It should support these public functions:

- `TeamStore.start_link(opts)` — starts the process. Accepts a `:name` option for registration.
- `TeamStore.create_user(server, id, token)` — stores a user with the given ID and bearer token. Returns `:ok`.
- `TeamStore.create_team(server, team_id)` — creates a team. Returns `:ok`.
- `TeamStore.add_member(server, team_id, user_id)` — adds a user to a team directly (for seeding). Returns `:ok`.
- `TeamStore.create_project(server, team_id, project_id)` — creates a project under a team. Returns `:ok`.
- `TeamStore.add_project_member(server, team_id, project_id, user_id)` — adds a user to a project directly (for seeding). Returns `:ok`.
- `TeamStore.get_user_by_token(server, token)` — returns `{:ok, user_id}` or `:error`.
- `TeamStore.team_exists?(server, team_id)` — returns `true` or `false`.
- `TeamStore.is_member?(server, team_id, user_id)` — returns `true` or `false` (team membership).
- `TeamStore.project_exists?(server, team_id, project_id)` — returns `true` or `false`.
- `TeamStore.is_project_member?(server, team_id, project_id, user_id)` — returns `true` or `false`.
- `TeamStore.list_projects(server, team_id)` — returns `{:ok, list_of_project_ids}` or `{:error, :not_found}`.
- `TeamStore.list_project_members(server, team_id, project_id)` — returns `{:ok, list_of_user_ids}` or `{:error, :not_found}`.
- `TeamStore.add_project_member_safe(server, team_id, project_id, user_id)` — adds a user to a project. Returns `{:ok, user_id}`; `{:error, :not_found}` if the project doesn't exist; `{:error, :not_team_member}` if the user is not a member of the parent team; or `{:error, :conflict}` if the user is already on the project.

**`AuthPlug`** — a Plug that reads the `authorization` header, expects `Bearer <token>`, looks the user up via `TeamStore.get_user_by_token/2`, and assigns `:current_user` to the conn. If the token is missing or invalid, it halts the connection with a 401 JSON response `{"error": "unauthorized"}`. It should accept a `:store` option at init time.

**`TeamRouter`** — a `Plug.Router` that serves the following endpoints. It should accept a `:store` option and plug `AuthPlug` before route matching. Authorization is evaluated in this exact order (return the first that applies):

- `GET /api/teams/:team_id/projects` — 404 `{"error": "not_found"}` if the team doesn't exist; 403 `{"error": "forbidden"}` if the current user is not a team member; otherwise 200 `{"projects": [list_of_project_ids]}`.

- `GET /api/teams/:team_id/projects/:project_id/members` — 404 if the team doesn't exist; 404 if the project doesn't exist; 403 if the current user is not a team member; 403 if the current user is not a project member; otherwise 200 `{"members": [list_of_user_ids]}`.

- `POST /api/teams/:team_id/projects/:project_id/members` — Reads a JSON body with `{"user_id": "..."}`. Same 404 (team) / 404 (project) / 403 (team member) / 403 (project member) cascade applies to the **acting** user. If the body is malformed / missing `user_id`, return 400 `{"error": "bad_request"}`. If the user being added is not a member of the parent team, return 422 `{"error": "not_a_team_member"}`. If the user is already on the project, return 409 `{"error": "conflict"}`. On success, return 201 `{"added": user_id}`.

All error and success responses must be `application/json`. Give me all modules in a single file. Use only `plug`, `jason`, and the OTP standard library.