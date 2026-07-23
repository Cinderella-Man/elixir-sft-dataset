# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

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

## The buggy module

```elixir
defmodule PathVersionApi.Migrations do
  @moduledoc """
  Versioning core for `PathVersionApi`.

  A single canonical latest representation (`"v3"`) is built from a stored user
  and older representations are produced by applying a descending downgrade
  migration chain (`v3 -> v2 -> v1`) rather than hand-written per-version
  renderers.
  """

  # Descending migration chain: latest first.
  @chain ["v3", "v2", "v1"]

  @doc """
  Returns the supported versions in ascending order, e.g. `["v1", "v2", "v3"]`.
  """
  @spec supported() :: [String.t()]
  def supported, do: Enum.reverse(@chain)

  @doc """
  Renders `user` under `id` for the requested `version`.

  Builds the canonical v3 document and applies each downgrade step needed to
  reach `version`.
  """
  @spec render(String.t(), String.t(), map()) :: map()
  def render(version, id, user) do
    user
    |> canonical(id)
    |> downgrade(version)
  end

  defp canonical(user, id) do
    %{
      id: id,
      name: %{first: user.first_name, last: user.last_name},
      email: user.email,
      created_at: user.created_at,
      country: user.country
    }
  end

  defp downgrade(doc, target) do
    target
    |> steps_to()
    |> Enum.reduce(doc, &apply_step/2)
  end

  defp steps_to(target) do
    idx = Enum.find_index(@chain, &(&1 == target))

    @chain
    |> Enum.take(idx + 1)
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.map(fn [from, to] -> {from, to} end)
  end

  defp apply_step({"v3", "v2"}, doc) do
    %{first: first, last: last} = doc.name

    doc
    |> Map.drop([:name, :country])
    |> Map.put(:first_name, first)
    |> Map.put(:last_name, last)
  end

  defp apply_step({"v2", "v1"}, doc) do
    full = doc.first_name <> " " <> doc.last_name

    doc
    |> Map.drop([:first_name, :last_name, :created_at])
    |> Map.put(:name, full)
  end
end

defmodule PathVersionApi.Router do
  @moduledoc """
  `Plug.Router` serving `GET /api/:version/users/:id`, where the API version is
  taken from the URL path and rendered via `PathVersionApi.Migrations`.

  An unsupported path version yields `400` before any user lookup; a valid
  version with an unknown id yields `404`. All responses are JSON.
  """

  use Plug.Router

  @users %{
    "1" => %{
      first_name: "Alice",
      last_name: "Smith",
      email: "alice@example.com",
      created_at: "2024-01-15T10:30:00Z",
      country: "US"
    },
    "2" => %{
      first_name: "Bob",
      last_name: "Jones",
      email: "bob@example.com",
      created_at: "2024-06-20T14:00:00Z",
      country: "GB"
    }
  }

  plug(:match)
  plug(:dispatch)

  get "/api/:version/users/:id" do
    supported = PathVersionApi.Migrations.supported()

    cond do
      version not in supported ->
        send_json(conn, 400, %{error: "unsupported version", supported: supported})

      true ->
        case Map.get(@users, id) do
          nil ->
            send_json(conn, 404, %{error: "not found"})

          user ->
            send_json(conn, 200, PathVersionApi.Migrations.render(version, id, user))
        end
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not found"})
  end

  defp send_json(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end
end
```

## Failing test report

```
6 of 13 test(s) failed:

  * test v2 flattens name and drops country
      
      
      Assertion with == failed
      code:  assert body["first_name"] == "Alice"
      left:  nil
      right: "Alice"
      

  * test v1 combines the name and drops created_at and country
      ** (FunctionClauseError) no function clause matching in anonymous fn/1 in PathVersionApi.Migrations.steps_to/1

  * test each version yields a distinct key set
      ** (FunctionClauseError) no function clause matching in anonymous fn/1 in PathVersionApi.Migrations.steps_to/1

  * test second user resolves through the chain in v1
      ** (FunctionClauseError) no function clause matching in anonymous fn/1 in PathVersionApi.Migrations.steps_to/1

  (…2 more)
```
