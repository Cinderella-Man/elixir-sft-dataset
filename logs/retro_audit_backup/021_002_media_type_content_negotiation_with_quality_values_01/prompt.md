Write me an Elixir Plug-based API module called `MediaVersionApi.Router` that serves a `GET /api/users/:id` endpoint, but instead of a custom `Accept-Version` header it performs **proper HTTP content negotiation** on the standard `Accept` header using vendor media types and quality (`q`) values.

I need these modules:

- `MediaVersionApi.Router` — a `Plug.Router` that defines the `GET /api/users/:id` route. It should run a negotiation plug (described below) before matching routes, look up the user by id from a simple in-memory data source (a module attribute map is fine), then delegate to a versioned view to render the response. If the user id is not found, return 404 with `{"error": "not found"}`. On success, the response `content-type` must echo the resolved vendor media type: `application/vnd.acme.<version>+json` (e.g. `application/vnd.acme.v1+json`).

- `MediaVersionApi.Plugs.AcceptVersion` — a custom Plug that parses the `Accept` request header and resolves the best acceptable version. It accepts a `:supported` option (list like `["v1", "v2"]`) and a `:default` option (string like `"v2"`). Parsing rules:
  - Each media range is `type[;q=Q]`; missing `q` defaults to `1.0`, and ranges with `q <= 0` are discarded.
  - A range of the form `application/vnd.acme.vN+json` maps to version `"vN"`.
  - The ranges `application/json`, `application/*`, and `*/*` all map to the `:default` version.
  - Any other media type maps to no version and is ignored.
  - Among the parsed ranges whose version is in `:supported`, pick the one with the **highest `q`**; ties are broken by earliest appearance in the header. Store it in `conn.assigns[:api_version]`.
  - If the `Accept` header is absent, assign the `:default` version.
  - If the header is present but no parsed range resolves to a supported version, halt with `406 Not Acceptable` and JSON body `{"error": "unsupported version", "supported": ["v1", "v2"]}` (content-type `application/json`).

- `MediaVersionApi.Views.UserView` — a module with `render(version, user)`:
  - `"v1"` returns `%{name: first_name <> " " <> last_name, email: email}`
  - `"v2"` returns `%{first_name: first_name, last_name: last_name, email: email, created_at: created_at}`

The in-memory user store should contain at least:

```
"1" => %{first_name: "Alice", last_name: "Smith", email: "alice@example.com", created_at: "2024-01-15T10:30:00Z"}
"2" => %{first_name: "Bob", last_name: "Jones", email: "bob@example.com", created_at: "2024-06-20T14:00:00Z"}
```

Use `Jason` for JSON encoding. Give me all three modules in a single file. Only depend on `plug`, `jason`, and their transitive dependencies — no Phoenix, no database.