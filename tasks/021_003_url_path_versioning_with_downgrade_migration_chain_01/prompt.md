# Path-Versioned User API — Specification

## Overview

This document specifies an Elixir Plug-based API module named `PathVersionApi.Router` that serves `GET /api/:version/users/:id`, where the version is carried in the **URL path** (for example, `/api/v1/users/1`). Older representations are not produced by hand-written per-version render functions; instead they are derived from a single canonical latest document by applying a **downgrade migration chain**.

The implementation comprises two modules. All modules are to be provided in a single file. The code may depend only on `plug`, `jason`, and their transitive dependencies — no Phoenix and no database. `Jason` is used for JSON encoding.

## API

### `PathVersionApi.Router`

A `Plug.Router` defining `GET /api/:version/users/:id`. It looks up the user by id in an in-memory map, validates the path version against the supported list, and renders via the migrations module.

### `PathVersionApi.Migrations`

The versioning core. There is one canonical latest representation (`"v3"`), built from the stored user, together with a descending migration chain `["v3", "v2", "v1"]`.

- `supported/0` returns `["v1", "v2", "v3"]` (ascending).
- `render(version, id, user)` builds the canonical v3 document, then applies each downgrade step needed to reach `version`:
  - Canonical **v3**: `%{id: id, name: %{first: first_name, last: last_name}, email: email, created_at: created_at, country: country}`.
  - Downgrade **v3 → v2**: flatten the nested `name` into top-level `first_name`/`last_name` and drop `country`. Result keys: `id, first_name, last_name, email, created_at`.
  - Downgrade **v2 → v1**: combine `first_name <> " " <> last_name` into a single `name` string and drop `created_at`. Result keys: `id, name, email`.

  Thus rendering v3 applies no steps, v2 applies `[v3→v2]`, and v1 applies `[v3→v2, v2→v1]` in order.

### In-memory user store

The in-memory user store is to contain at least:

```
"1" => %{first_name: "Alice", last_name: "Smith", email: "alice@example.com", created_at: "2024-01-15T10:30:00Z", country: "US"}
"2" => %{first_name: "Bob", last_name: "Jones", email: "bob@example.com", created_at: "2024-06-20T14:00:00Z", country: "GB"}
```

## Edge cases

Validation order matters:

- If the path `version` is not supported, the router returns `400 Bad Request` with `{"error": "unsupported version", "supported": ["v1", "v2", "v3"]}` **before** any user lookup is performed.
- If the user id is not found (and the version is valid), the router returns 404 with `{"error": "not found"}`.
- On a successful lookup, the router returns `200 OK` with the rendered document.
- Any request that does not match `GET /api/:version/users/:id` (a different path or method) likewise returns 404 with `{"error": "not found"}`.

All responses use `content-type` `application/json`.
