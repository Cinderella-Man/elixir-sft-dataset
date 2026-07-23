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
