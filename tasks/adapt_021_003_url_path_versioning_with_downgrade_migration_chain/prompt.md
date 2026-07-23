# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

```elixir
<file path="lib/versioned_api/views/user_view.ex">
defmodule VersionedApi.Views.UserView do
  @moduledoc "Renders a user map per API version: v1 is a flat name, v2 is structured."

  @doc ~s|Renders `u` for API `version` ("v1" or "v2") as a plain map.|
  @spec render(String.t(), map()) :: map()
  def render("v1", u), do: %{name: u.first_name <> " " <> u.last_name, email: u.email}

  def render("v2", u) do
    %{first_name: u.first_name, last_name: u.last_name, email: u.email, created_at: u.created_at}
  end
end
</file>
<file path="lib/versioned_api/plugs/api_version.ex">
defmodule VersionedApi.Plugs.ApiVersion do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, opts) do
    supported = Keyword.get(opts, :supported, ["v1", "v2"])
    default = Keyword.get(opts, :default, "v2")

    version =
      case get_req_header(conn, "accept-version") do
        [v | _] -> v
        [] -> default
      end

    if version in supported do
      assign(conn, :api_version, version)
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(406, Jason.encode!(%{error: "unsupported version", supported: supported}))
      |> halt()
    end
  end
end
</file>
<file path="lib/versioned_api/router.ex">
defmodule VersionedApi.Router do
  use Plug.Router

  @users %{
    "1" => %{
      first_name: "Alice",
      last_name: "Smith",
      email: "alice@example.com",
      created_at: "2024-01-15T10:30:00Z"
    },
    "2" => %{
      first_name: "Bob",
      last_name: "Jones",
      email: "bob@example.com",
      created_at: "2024-06-20T14:00:00Z"
    }
  }
  plug(VersionedApi.Plugs.ApiVersion, supported: ["v1", "v2"], default: "v2")
  plug(:match)
  plug(:dispatch)

  get "/api/users/:id" do
    case Map.get(@users, id) do
      nil ->
        send_json(conn, 404, %{error: "not found"})

      user ->
        rendered = VersionedApi.Views.UserView.render(conn.assigns.api_version, user)
        send_json(conn, 200, rendered)
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not found"})
  end

  defp send_json(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end
end
</file>
```

## New specification

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
