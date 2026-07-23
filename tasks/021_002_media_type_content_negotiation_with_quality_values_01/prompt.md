# MediaVersionApi — Media-Type Content Negotiation Specification

## Overview

This document specifies an Elixir Plug-based API module named `MediaVersionApi.Router` that serves a `GET /api/users/:id` endpoint. Rather than relying on a custom `Accept-Version` header, the implementation performs **proper HTTP content negotiation** on the standard `Accept` header using vendor media types and quality (`q`) values.

Three modules are required. JSON encoding is done with `Jason`. All three modules are to be provided in a single file. The implementation may only depend on `plug`, `jason`, and their transitive dependencies — no Phoenix and no database.

## API

The following modules make up the deliverable.

### `MediaVersionApi.Router`

This is a `Plug.Router` that defines the `GET /api/users/:id` route. It runs a negotiation plug (described below) before matching routes, looks up the user by id from a simple in-memory data source (a module attribute map is acceptable), then delegates to a versioned view to render the response.

- If the user id is not found, it returns 404 with JSON body `{"error": "not found"}` and content-type `application/json`.
- Any request that does not match the route returns the same 404 response.
- On success, the response `content-type` echoes the resolved vendor media type: `application/vnd.acme.<version>+json` (e.g. `application/vnd.acme.v1+json`).

### `MediaVersionApi.Plugs.AcceptVersion`

This is a custom Plug that parses the `Accept` request header and resolves the best acceptable version. It accepts a `:supported` option (list like `["v1", "v2"]`) and a `:default` option (string like `"v2"`). Parsing rules:

- Each media range is `type[;q=Q]`; missing `q` defaults to `1.0`, and ranges with `q <= 0` are discarded.
- A range of the form `application/vnd.acme.vN+json` maps to version `"vN"`.
- The ranges `application/json`, `application/*`, and `*/*` all map to the `:default` version.
- Any other media type maps to no version and is ignored.
- Among the parsed ranges whose version is in `:supported`, the one with the **highest `q`** is picked; ties are broken by earliest appearance in the header. The result is stored in `conn.assigns[:api_version]`.
- If the `Accept` header is absent, the `:default` version is assigned.
- If the header is present but no parsed range resolves to a supported version, the plug halts with `406 Not Acceptable` and JSON body `{"error": "unsupported version", "supported": <the configured :supported list>}` (for the default options, `["v1", "v2"]`; content-type `application/json`).

### `MediaVersionApi.Views.UserView`

This module provides `render(version, user)`:

- `"v1"` returns `%{name: first_name <> " " <> last_name, email: email}`
- `"v2"` returns `%{first_name: first_name, last_name: last_name, email: email, created_at: created_at}`

### In-memory user store

The in-memory user store contains at least:

```
"1" => %{first_name: "Alice", last_name: "Smith", email: "alice@example.com", created_at: "2024-01-15T10:30:00Z"}
"2" => %{first_name: "Bob", last_name: "Jones", email: "bob@example.com", created_at: "2024-06-20T14:00:00Z"}
```

## Edge cases

- A user id that is not found yields a 404 response with JSON body `{"error": "not found"}` and content-type `application/json`.
- Any request that does not match the route yields the same 404 response.
- Media ranges with missing `q` are treated as `1.0`; ranges with `q <= 0` are discarded.
- Media types other than `application/vnd.acme.vN+json`, `application/json`, `application/*`, and `*/*` map to no version and are ignored.
- When multiple supported ranges are present, the highest `q` wins, with ties broken by earliest appearance in the header.
- An absent `Accept` header results in the `:default` version being assigned.
- A present `Accept` header that resolves to no supported version causes a halt with `406 Not Acceptable` and JSON body `{"error": "unsupported version", "supported": <the configured :supported list>}` (for the default options, `["v1", "v2"]`; content-type `application/json`).
