# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

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

## Module under test

```elixir
<file path="lib/versioned_api/views/user_view.ex">
defmodule VersionedApi.Views.UserView do
  def render("v1", u), do: %{name: u.first_name <> " " <> u.last_name, email: u.email}
  def render("v2", u), do: %{first_name: u.first_name, last_name: u.last_name, email: u.email, created_at: u.created_at}
end
</file>
<file path="lib/versioned_api/plugs/api_version.ex">
defmodule VersionedApi.Plugs.ApiVersion do
  import Plug.Conn
  def init(opts), do: opts
  def call(conn, opts) do
    supported = Keyword.get(opts, :supported, ["v1", "v2"])
    default = Keyword.get(opts, :default, "v2")
    version = case get_req_header(conn, "accept-version") do
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
    "1" => %{first_name: "Alice", last_name: "Smith", email: "alice@example.com", created_at: "2024-01-15T10:30:00Z"},
    "2" => %{first_name: "Bob", last_name: "Jones", email: "bob@example.com", created_at: "2024-06-20T14:00:00Z"}
  }
  plug VersionedApi.Plugs.ApiVersion, supported: ["v1", "v2"], default: "v2"
  plug :match
  plug :dispatch
  get "/api/users/:id" do
    case Map.get(@users, id) do
      nil -> send_json(conn, 404, %{error: "not found"})
      user -> send_json(conn, 200, VersionedApi.Views.UserView.render(conn.assigns.api_version, user))
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
