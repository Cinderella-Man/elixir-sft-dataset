# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

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
