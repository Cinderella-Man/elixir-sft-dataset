# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `send_error` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

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

## The module with `send_error` missing

```elixir
defmodule MediaVersionApi.Views.UserView do
  @moduledoc """
  Renders a user map into a versioned representation.

  Version `"v1"` exposes a combined `name` field, while version `"v2"` exposes
  the individual name fields together with `created_at`.
  """

  @doc """
  Renders `user` according to the requested API `version` (`"v1"` or `"v2"`).
  """
  @spec render(String.t(), map()) :: map()
  def render("v1", u), do: %{name: u.first_name <> " " <> u.last_name, email: u.email}

  def render("v2", u),
    do: %{
      first_name: u.first_name,
      last_name: u.last_name,
      email: u.email,
      created_at: u.created_at
    }
end

defmodule MediaVersionApi.Plugs.AcceptVersion do
  @moduledoc """
  A `Plug` that performs HTTP content negotiation on the standard `Accept`
  header using vendor media types (`application/vnd.acme.vN+json`) and quality
  (`q`) values.

  Options:

    * `:supported` — list of supported versions, e.g. `["v1", "v2"]`.
    * `:default` — version used for generic/wildcard media types and when the
      `Accept` header is absent.

  On success the resolved version is stored in `conn.assigns[:api_version]`.
  When the header is present but nothing acceptable is found, the connection is
  halted with a `406 Not Acceptable` JSON response.
  """

  import Plug.Conn

  @vendor "application/vnd.acme."

  @doc """
  Initializes the plug; returns the given options unchanged.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Negotiates the API version from the `Accept` header and assigns it, or halts
  with `406` when no supported version is acceptable.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    supported = Keyword.get(opts, :supported, ["v1", "v2"])
    default = Keyword.get(opts, :default, "v2")

    case get_req_header(conn, "accept") do
      [] -> assign(conn, :api_version, default)
      [accept | _] -> resolve(conn, accept, supported, default)
    end
  end

  defp resolve(conn, accept, supported, default) do
    version =
      accept
      |> parse_accept(default)
      |> Enum.filter(fn {v, _q} -> v in supported end)
      |> best_version()

    case version do
      nil ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(406, Jason.encode!(%{error: "unsupported version", supported: supported}))
        |> halt()

      v ->
        assign(conn, :api_version, v)
    end
  end

  defp parse_accept(accept, default) do
    accept
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_media_range(&1, default))
    |> Enum.reject(fn {v, q} -> is_nil(v) or q <= 0 end)
  end

  defp parse_media_range(range, default) do
    [type | params] = range |> String.split(";") |> Enum.map(&String.trim/1)
    {version_for(type, default), parse_q(params)}
  end

  defp version_for(type, default) do
    cond do
      String.starts_with?(type, @vendor) and String.ends_with?(type, "+json") ->
        type
        |> String.replace_prefix(@vendor, "")
        |> String.replace_suffix("+json", "")

      type in ["application/json", "application/*", "*/*"] ->
        default

      true ->
        nil
    end
  end

  defp parse_q(params) do
    Enum.find_value(params, 1.0, fn p ->
      case String.split(p, "=") do
        ["q", val] ->
          case Float.parse(val) do
            {f, _} -> f
            :error -> 1.0
          end

        _ ->
          nil
      end
    end)
  end

  defp best_version([]), do: nil

  defp best_version(list) do
    {{v, _q}, _idx} =
      list
      |> Enum.with_index()
      |> Enum.max_by(fn {{_v, q}, idx} -> {q, -idx} end)

    v
  end
end

defmodule MediaVersionApi.Router do
  @moduledoc """
  A `Plug.Router` serving `GET /api/users/:id`.

  It negotiates the API version via `MediaVersionApi.Plugs.AcceptVersion`, looks
  up the user in an in-memory store, and renders the response with
  `MediaVersionApi.Views.UserView`. Successful responses echo the resolved
  vendor media type (`application/vnd.acme.<version>+json`).
  """

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

  plug(MediaVersionApi.Plugs.AcceptVersion, supported: ["v1", "v2"], default: "v2")
  plug(:match)
  plug(:dispatch)

  get "/api/users/:id" do
    version = conn.assigns.api_version

    case Map.get(@users, id) do
      nil ->
        send_error(conn, 404, %{error: "not found"})

      user ->
        body = MediaVersionApi.Views.UserView.render(version, user)

        conn
        |> put_resp_content_type("application/vnd.acme.#{version}+json")
        |> send_resp(200, Jason.encode!(body))
    end
  end

  match _ do
    send_error(conn, 404, %{error: "not found"})
  end

  defp send_error(conn, status, body) do
    # TODO
  end
end
```

Reply with `send_error` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
