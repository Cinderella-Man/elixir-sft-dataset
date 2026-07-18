# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule LifecycleApi.Views.UserView do
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
  import Plug.Conn

  @statuses %{"v0" => :retired, "v1" => :deprecated, "v2" => :active}
  @sunsets %{"v1" => "Sat, 01 Nov 2025 00:00:00 GMT"}

  def init(opts), do: opts

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
