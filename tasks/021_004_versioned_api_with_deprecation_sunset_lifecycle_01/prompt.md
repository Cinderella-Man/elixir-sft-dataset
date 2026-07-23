# Ticket: `LifecycleApi.Router` — versioned user API with lifecycle status

Build an Elixir Plug-based API. Serve `GET /api/users/:id` with version selection via the `Accept-Version` header, where each version has a **lifecycle status** that changes response semantics: active versions serve normally, deprecated versions serve with sunset/deprecation headers, retired versions are refused with `410 Gone`. Deliver all three modules in a single file.

**Deliverable — `LifecycleApi.Router`**
- A `Plug.Router` defining `GET /api/users/:id`.
- Run the version plug before matching routes.
- Look up the user in an in-memory map, render via the versioned view.
- Missing user → 404 `{"error": "not found"}`.
- All success/404 responses use `content-type` `application/json`.

**Deliverable — `LifecycleApi.Plugs.ApiVersion`**
- Custom Plug with a version registry mapping version → status:
  - `"v0"` → `:retired`
  - `"v1"` → `:deprecated`
  - `"v2"` → `:active`
- Accept a `:default` option (default `"v2"`).
- Read the `accept-version` header; if absent, use the default. Then dispatch by status.

**Behavior by status**
- **unknown** version (not in the registry) → halt with `406 Not Acceptable` and `{"error": "unsupported version", "supported": [...]}`, where `supported` is the sorted list of requestable (active + deprecated) versions.
- **`:retired`** → halt with `410 Gone` and `{"error": "version retired", "version": "<v>", "supported": [...]}` (same requestable list). This must happen even when the user id does not exist — the plug halts before route dispatch.
- **`:deprecated`** → assign the version to `conn.assigns[:api_version]` and add response headers: `deprecation: true`, `sunset: <RFC-1123 date>` (use `"Sat, 01 Nov 2025 00:00:00 GMT"` for v1), and `warning: 299 - "Deprecated API version <v>"`. Then continue.
- **`:active`** → assign the version and continue with no extra headers.

**Response format — plug halts**
- The 406/410 halting responses use `content-type` `application/json`.

**Deliverable — `LifecycleApi.Views.UserView`**
- `render(version, user)`:
  - `"v1"` returns `%{name: first_name <> " " <> last_name, email: email}`
  - `"v2"` returns `%{first_name: first_name, last_name: last_name, email: email, created_at: created_at}`

**In-memory user store — contains at least**
```
"1" => %{first_name: "Alice", last_name: "Smith", email: "alice@example.com", created_at: "2024-01-15T10:30:00Z"}
"2" => %{first_name: "Bob", last_name: "Jones", email: "bob@example.com", created_at: "2024-06-20T14:00:00Z"}
```

**Constraints**
- Use `Jason` for JSON encoding.
- All three modules in a single file.
- Only depend on `plug`, `jason`, and their transitive dependencies — no Phoenix, no database.
