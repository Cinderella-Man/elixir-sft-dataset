Implement the public `call/2` function for the `VersionedApi.Plugs.ApiVersion` plug.
It receives the `conn` and the plug's `opts` (the keyword list returned by `init/1`).
Read the `:supported` option (defaulting to `["v1", "v2"]`) and the `:default` option
(defaulting to `"v2"`). Determine the requested version by reading the `accept-version`
request header with `get_req_header/2`: if the header is present, use its first value;
if it is absent, use the default version. If the resolved version is in the supported
list, assign it to `conn.assigns[:api_version]` using `assign/3` and return the conn.
Otherwise, respond with `406 Not Acceptable`: set the `content-type` to
`application/json`, send a JSON body of `%{error: "unsupported version", supported: supported}`
encoded with `Jason`, and `halt/1` the connection.

```elixir
defmodule VersionedApi.Views.UserView do
  def render("v1", u), do: %{name: u.first_name <> " " <> u.last_name, email: u.email}

  def render("v2", u),
    do: %{
      first_name: u.first_name,
      last_name: u.last_name,
      email: u.email,
      created_at: u.created_at
    }
end

defmodule VersionedApi.Plugs.ApiVersion do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, opts) do
    # TODO
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
        send_json(conn, 200, VersionedApi.Views.UserView.render(conn.assigns.api_version, user))
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