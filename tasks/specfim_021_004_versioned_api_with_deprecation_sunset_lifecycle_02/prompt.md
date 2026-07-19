# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`render/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `render/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `render/2` missing

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
  # TODO: @spec
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
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
