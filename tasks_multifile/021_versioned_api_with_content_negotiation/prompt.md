Write me an Elixir Plug-based API module called `VersionedApi.Router` that serves a `GET /api/users/:id` endpoint returning different JSON response shapes depending on the `Accept-Version` request header.

I need these modules:

- `VersionedApi.Router` — a `Plug.Router` that defines the `GET /api/users/:id` route. It should use a version plug (described below) before matching routes. The route handler should look up the user by id from a simple in-memory data source (a module attribute map is fine — no database needed), then delegate to a versioned view to render the response. If the user id is not found, return 404 with `{"error": "not found"}`.

- `VersionedApi.Plugs.ApiVersion` — a custom Plug that extracts the `accept-version` header, validates it against a list of supported versions, and stores the resolved version in `conn.assigns[:api_version]`. It should accept a `:supported` option (list of strings like `["v1", "v2"]`) and a `:default` option (string like `"v2"`). If no `Accept-Version` header is present, assign the default version. If the header value is not in the supported list, halt the connection and return `406 Not Acceptable` with the JSON body `{"error": "unsupported version", "supported": ["v1", "v2"]}`.

- `VersionedApi.Views.UserView` — a module with a `render(version, user)` function that returns a map with the appropriate shape:
  - `"v1"` returns `%{name: first_name <> " " <> last_name, email: email}`
  - `"v2"` returns `%{first_name: first_name, last_name: last_name, email: email, created_at: created_at}`

The in-memory user store should contain at least these entries:

```
"1" => %{first_name: "Alice", last_name: "Smith", email: "alice@example.com", created_at: "2024-01-15T10:30:00Z"}
"2" => %{first_name: "Bob", last_name: "Jones", email: "bob@example.com", created_at: "2024-06-20T14:00:00Z"}
```

All JSON responses must have a `content-type` of `application/json`. Use `Jason` for JSON encoding.

Give me all three modules in a single file. Only depend on `plug`, `jason`, and their transitive dependencies — no Phoenix, no database.