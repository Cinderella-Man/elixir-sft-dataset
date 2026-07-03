Implement the private `parse_q/1` function. It receives `params`, the list of
parameter strings that followed the media type in a single `Accept` media range
(each already trimmed, e.g. `["q=0.8"]`, `["level=1", "q=0.5"]`, or `[]`). Its
job is to extract the quality (`q`) value for that range as a float.

Walk the parameters and look for one of the form `q=<value>`: split each
parameter on `"="`, and when you find a pair whose key is exactly `"q"`, parse
its value with `Float.parse/1`, returning the parsed float on success or `1.0`
if the value cannot be parsed as a float. Any parameter that is not a `q=`
pair should be skipped. If no `q` parameter is present at all, default to `1.0`.

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
    do: %{first_name: u.first_name, last_name: u.last_name, email: u.email, created_at: u.created_at}
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
    # TODO
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

  plug MediaVersionApi.Plugs.AcceptVersion, supported: ["v1", "v2"], default: "v2"
  plug :match
  plug :dispatch

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
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end
end
```