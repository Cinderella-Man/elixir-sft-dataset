Implement the private `send_json/3` helper function. It takes a `conn`, an HTTP
`status` code, and a `body` term. It should set the response content type to
`application/json`, then send the response with the given `status` and the `body`
encoded to JSON via `Jason.encode!/1`. Return the resulting `conn`.

```elixir
defmodule VersionedApi.Plugs.ApiVersion do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    supported = Keyword.fetch!(opts, :supported)
    default = Keyword.fetch!(opts, :default)

    case get_req_header(conn, "accept-version") do
      [] ->
        assign(conn, :api_version, default)

      [v | _] ->
        if v in supported do
          assign(conn, :api_version, v)
        else
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            406,
            Jason.encode!(%{error: "unsupported version", supported: supported})
          )
          |> halt()
        end
    end
  end
end

defmodule VersionedApi.Views.UserView do
  def render("v1", user) do
    %{name: "#{user.first_name} #{user.last_name}", email: user.email}
  end

  def render("v2", user) do
    %{
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      created_at: user.created_at
    }
  end
end

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
    # TODO
  end
end
```