Implement the private `send_json/3` helper function. It takes a `conn`, an HTTP
`status` code, and a `body` term. It should set the response content type to
`application/json`, then send the response with the given `status` and the `body`
encoded to JSON via `Jason.encode!/1`. Return the resulting `conn`.

```elixir
defmodule VersionedApi.Views.UserView do
  @moduledoc "Renders a user map per API version: v1 is a flat name, v2 is structured."

  @doc ~s|Renders `u` for API `version` ("v1" or "v2") as a plain map.|
  @spec render(String.t(), map()) :: map()
  def render("v1", u), do: %{name: u.first_name <> " " <> u.last_name, email: u.email}

  def render("v2", u) do
    %{first_name: u.first_name, last_name: u.last_name, email: u.email, created_at: u.created_at}
  end
end

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