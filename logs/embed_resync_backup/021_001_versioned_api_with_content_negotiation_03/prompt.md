# Fill in the middle: `VersionedApi.Views.UserView.render/2`

This project is a small Plug-based versioned JSON API. A request to
`GET /api/users/:id` is processed by the `VersionedApi.Plugs.ApiVersion` plug,
which resolves the requested API version from the `Accept-Version` header and
stores it in `conn.assigns[:api_version]`. The router looks the user up in an
in-memory map and delegates rendering to `VersionedApi.Views.UserView.render/2`.

Implement the body of the public `render/2` function in
`VersionedApi.Views.UserView`. It takes the resolved API version string as its
first argument and a user map as its second argument, and returns a plain map
describing the response shape for that version (the caller is responsible for
JSON-encoding the returned map).

Support these two versions:

- `"v1"` — return a map with two keys: `:name`, whose value is the user's
  `first_name` and `last_name` joined by a single space (`first_name <> " " <> last_name`),
  and `:email`, the user's email.
- `"v2"` — return a map with four keys: `:first_name`, `:last_name`, `:email`,
  and `:created_at`, each taken directly from the corresponding field of the
  user map.

Branch on the version string (for example with a `case`) inside the function body.

```elixir
defmodule VersionedApi.Views.UserView do
  def render(version, user) do
    # TODO
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