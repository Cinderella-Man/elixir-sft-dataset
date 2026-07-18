Write me an Elixir Plug-based API module called `PathVersionApi.Router` that serves `GET /api/:version/users/:id` where the version lives in the **URL path** (e.g. `/api/v1/users/1`), and where older representations are produced by a **downgrade migration chain** applied to a single canonical latest document rather than by hand-written per-version render functions.

I need these modules:

- `PathVersionApi.Router` — a `Plug.Router` defining `GET /api/:version/users/:id`. It looks up the user by id in an in-memory map, validates the path version against the supported list, and renders via the migrations module. Validation order matters: if the path `version` is not supported, return `400 Bad Request` with `{"error": "unsupported version", "supported": ["v1", "v2", "v3"]}` **before** any user lookup. If the user id is not found (and the version is valid), return 404 with `{"error": "not found"}`. On a successful lookup, return `200 OK` with the rendered document. Any request that does not match `GET /api/:version/users/:id` (a different path or method) returns 404 with `{"error": "not found"}` as well. All responses use `content-type` `application/json`.

- `PathVersionApi.Migrations` — the versioning core. There is one canonical latest representation (`"v3"`) built from the stored user, and a descending migration chain `["v3", "v2", "v1"]`. `supported/0` returns `["v1", "v2", "v3"]` (ascending). `render(version, id, user)` builds the canonical v3 document, then applies each downgrade step needed to reach `version`:
  - Canonical **v3**: `%{id: id, name: %{first: first_name, last: last_name}, email: email, created_at: created_at, country: country}`.
  - Downgrade **v3 → v2**: flatten the nested `name` into top-level `first_name`/`last_name` and drop `country`. Result keys: `id, first_name, last_name, email, created_at`.
  - Downgrade **v2 → v1**: combine `first_name <> " " <> last_name` into a single `name` string and drop `created_at`. Result keys: `id, name, email`.

  So rendering v3 applies no steps, v2 applies `[v3→v2]`, and v1 applies `[v3→v2, v2→v1]` in order.

The in-memory user store should contain at least:

```
"1" => %{first_name: "Alice", last_name: "Smith", email: "alice@example.com", created_at: "2024-01-15T10:30:00Z", country: "US"}
"2" => %{first_name: "Bob", last_name: "Jones", email: "bob@example.com", created_at: "2024-06-20T14:00:00Z", country: "GB"}
```

Use `Jason` for JSON encoding. Give me all modules in a single file. Only depend on `plug`, `jason`, and their transitive dependencies — no Phoenix, no database.
