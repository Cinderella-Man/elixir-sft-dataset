# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `send_json`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

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

## The module with `send_json` missing

```elixir
defmodule LifecycleApi.Views.UserView do
  @moduledoc """
  Versioned rendering of a user map.

  Each API version maps a stored user to the JSON-serialisable shape that
  version promises to its clients.
  """

  @doc """
  Renders `user` into the response shape for the given API `version`.

  `"v1"` returns a combined `name` and the `email`; `"v2"` returns the
  individual name fields plus `email` and `created_at`.
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

defmodule LifecycleApi.Plugs.ApiVersion do
  @moduledoc """
  Plug that selects an API version from the `accept-version` request header
  and enforces its lifecycle status.

  Unknown versions are refused with `406 Not Acceptable`, retired versions
  with `410 Gone` (halting before route dispatch), deprecated versions are
  served with sunset/deprecation headers, and active versions pass through.
  """

  import Plug.Conn

  @statuses %{"v0" => :retired, "v1" => :deprecated, "v2" => :active}
  @sunsets %{"v1" => "Sat, 01 Nov 2025 00:00:00 GMT"}

  @doc """
  Initialises the plug, returning its options unchanged.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Resolves the requested version and applies its lifecycle behaviour to `conn`.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    default = Keyword.get(opts, :default, "v2")

    version =
      case get_req_header(conn, "accept-version") do
        [v | _] -> v
        [] -> default
      end

    case Map.get(@statuses, version) do
      nil ->
        halt_json(conn, 406, %{error: "unsupported version", supported: requestable()})

      :retired ->
        halt_json(conn, 410, %{
          error: "version retired",
          version: version,
          supported: requestable()
        })

      :deprecated ->
        conn
        |> assign(:api_version, version)
        |> put_deprecation_headers(version)

      :active ->
        assign(conn, :api_version, version)
    end
  end

  defp requestable do
    @statuses
    |> Enum.filter(fn {_v, status} -> status in [:active, :deprecated] end)
    |> Enum.map(fn {v, _status} -> v end)
    |> Enum.sort()
  end

  defp put_deprecation_headers(conn, version) do
    conn
    |> put_resp_header("deprecation", "true")
    |> put_sunset(version)
    |> put_resp_header("warning", ~s(299 - "Deprecated API version #{version}"))
  end

  defp put_sunset(conn, version) do
    case Map.get(@sunsets, version) do
      nil -> conn
      date -> put_resp_header(conn, "sunset", date)
    end
  end

  defp halt_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end
end

defmodule LifecycleApi.Router do
  @moduledoc """
  Plug router serving `GET /api/users/:id` with lifecycle-aware version
  selection.

  It runs `LifecycleApi.Plugs.ApiVersion` before matching, looks the user up
  in an in-memory store, and renders the response through
  `LifecycleApi.Views.UserView`. Missing users and unmatched routes return a
  JSON `404`.
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

  plug(LifecycleApi.Plugs.ApiVersion, default: "v2")
  plug(:match)
  plug(:dispatch)

  get "/api/users/:id" do
    case Map.get(@users, id) do
      nil ->
        send_json(conn, 404, %{error: "not found"})

      user ->
        send_json(conn, 200, LifecycleApi.Views.UserView.render(conn.assigns.api_version, user))
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not found"})
  end

  defp send_json(conn, status, body) do
    # TODO
  end
end
```

Output only `send_json` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
