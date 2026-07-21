# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
    do: %{
      first_name: u.first_name,
      last_name: u.last_name,
      email: u.email,
      created_at: u.created_at
    }
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
    Enum.find_value(params, 1.0, fn p ->
      case String.split(p, "=") do
        ["q", val] ->
          case Float.parse(val) do
            {f, _} -> f
            :error -> 1.0
          end

        _ ->
          nil
      end
    end)
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

  plug(MediaVersionApi.Plugs.AcceptVersion, supported: ["v1", "v2"], default: "v2")
  plug(:match)
  plug(:dispatch)

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

## Test harness — implement the `# TODO` test

```elixir
defmodule MediaVersionApi.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test

  @opts MediaVersionApi.Router.init([])

  defp call(path, headers \\ []) do
    conn =
      Enum.reduce(headers, conn(:get, path), fn {k, v}, c ->
        Plug.Conn.put_req_header(c, k, v)
      end)

    MediaVersionApi.Router.call(conn, @opts)
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  defp content_type(conn) do
    {"content-type", ct} = List.keyfind(conn.resp_headers, "content-type", 0)
    ct
  end

  # -------------------------------------------------------
  # Vendor media type selects the version
  # -------------------------------------------------------

  test "v1 vendor media type returns v1 shape" do
    conn = call("/api/users/1", [{"accept", "application/vnd.acme.v1+json"}])

    assert conn.status == 200
    body = json_body(conn)

    assert body["name"] == "Alice Smith"
    assert body["email"] == "alice@example.com"
    refute Map.has_key?(body, "first_name")
    refute Map.has_key?(body, "created_at")
  end

  test "v2 vendor media type returns v2 shape" do
    conn = call("/api/users/1", [{"accept", "application/vnd.acme.v2+json"}])

    assert conn.status == 200
    body = json_body(conn)

    assert body["first_name"] == "Alice"
    assert body["last_name"] == "Smith"
    assert body["created_at"] == "2024-01-15T10:30:00Z"
    refute Map.has_key?(body, "name")
  end

  test "success response echoes the resolved vendor content-type" do
    conn = call("/api/users/1", [{"accept", "application/vnd.acme.v1+json"}])
    assert content_type(conn) =~ "application/vnd.acme.v1+json"

    conn2 = call("/api/users/1", [{"accept", "application/vnd.acme.v2+json"}])
    assert content_type(conn2) =~ "application/vnd.acme.v2+json"
  end

  # -------------------------------------------------------
  # Quality values
  # -------------------------------------------------------

  test "highest q value wins" do
    conn =
      call("/api/users/1", [
        {"accept", "application/vnd.acme.v2+json;q=0.5, application/vnd.acme.v1+json;q=0.9"}
      ])

    assert conn.status == 200
    assert json_body(conn)["name"] == "Alice Smith"
    assert content_type(conn) =~ "v1"
  end

  test "equal q values break ties by earliest appearance" do
    conn =
      call("/api/users/1", [
        {"accept", "application/vnd.acme.v1+json, application/vnd.acme.v2+json"}
      ])

    assert content_type(conn) =~ "v1"
  end

  test "unsupported vendor version is skipped in favor of a supported one" do
    conn =
      call("/api/users/1", [
        {"accept", "application/vnd.acme.v9+json;q=1.0, application/vnd.acme.v1+json;q=0.3"}
      ])

    assert conn.status == 200
    assert content_type(conn) =~ "v1"
  end

  # A range without q carries q=1.0, so it outranks any explicit lower q no
  # matter where it appears in the header.
  test "missing q defaults to 1.0 and outranks an explicit lower q" do
    conn =
      call("/api/users/1", [
        {"accept", "application/vnd.acme.v1+json, application/vnd.acme.v2+json;q=0.9"}
      ])

    assert conn.status == 200
    assert content_type(conn) =~ "v1"
    assert json_body(conn)["name"] == "Alice Smith"

    later =
      call("/api/users/1", [
        {"accept", "application/vnd.acme.v2+json;q=0.9, application/vnd.acme.v1+json"}
      ])

    assert later.status == 200
    assert content_type(later) =~ "v1"
  end

  # -------------------------------------------------------
  # q <= 0 discards the range
  # -------------------------------------------------------

  test "supported vendor range with q=0 is discarded and yields 406" do
    conn = call("/api/users/1", [{"accept", "application/vnd.acme.v1+json;q=0"}])

    assert conn.status == 406
    body = json_body(conn)
    assert body["error"] =~ "unsupported"
    assert "v1" in body["supported"]
    assert "v2" in body["supported"]
    assert content_type(conn) =~ "application/json"
  end

  test "range with negative q is discarded and yields 406" do
    conn = call("/api/users/1", [{"accept", "application/vnd.acme.v2+json;q=-0.5"}])

    assert conn.status == 406
  end

  test "wildcard with q=0 does not resolve to the default version" do
    conn = call("/api/users/1", [{"accept", "*/*;q=0"}])

    assert conn.status == 406
  end

  # A discarded q=0 range cannot win a tie against another q=0 range either:
  # both are gone, so nothing acceptable remains.
  test "all ranges at q=0 leave nothing acceptable" do
    conn =
      call("/api/users/1", [
        {"accept", "application/vnd.acme.v1+json;q=0, application/vnd.acme.v2+json;q=0"}
      ])

    assert conn.status == 406
  end

  # -------------------------------------------------------
  # Wildcards and generic json map to default
  # -------------------------------------------------------

  test "*/* resolves to the default version" do
    # TODO
  end

  test "application/json resolves to the default version" do
    conn = call("/api/users/1", [{"accept", "application/json"}])
    assert content_type(conn) =~ "v2"
  end

  test "absent Accept header resolves to the default version" do
    conn = call("/api/users/1")
    assert conn.status == 200
    assert content_type(conn) =~ "v2"
    assert Map.has_key?(json_body(conn), "first_name")
  end

  # -------------------------------------------------------
  # 406 when nothing acceptable
  # -------------------------------------------------------

  test "only-unsupported vendor version returns 406" do
    conn = call("/api/users/1", [{"accept", "application/vnd.acme.v9+json"}])

    assert conn.status == 406
    body = json_body(conn)
    assert body["error"] =~ "unsupported"
    assert "v1" in body["supported"]
    assert "v2" in body["supported"]
    assert content_type(conn) =~ "application/json"
  end

  test "unrelated media type only returns 406" do
    conn = call("/api/users/1", [{"accept", "text/html"}])
    assert conn.status == 406
  end

  test "406 halts before user lookup even for a missing user" do
    conn = call("/api/users/999", [{"accept", "application/vnd.acme.v9+json"}])
    assert conn.status == 406
  end

  # -------------------------------------------------------
  # Not found
  # -------------------------------------------------------

  test "missing user returns 404 with json content type" do
    conn = call("/api/users/999", [{"accept", "application/vnd.acme.v2+json"}])
    assert conn.status == 404
    assert json_body(conn)["error"] =~ "not found"
    assert content_type(conn) =~ "application/json"
  end

  test "second user is correct in v1" do
    conn = call("/api/users/2", [{"accept", "application/vnd.acme.v1+json"}])
    body = json_body(conn)
    assert body["name"] == "Bob Jones"
    assert body["email"] == "bob@example.com"
  end

  test "unmatched route returns 404" do
    conn = call("/api/nope")
    assert conn.status == 404
  end

  # A request that matches no route gets the same 404 payload as a missing
  # user: a JSON body carrying the "not found" error, served as
  # application/json — not an empty or plain-text body.
  test "unmatched route returns the same json 404 body as a missing user" do
    conn = call("/api/nope")

    assert conn.status == 404
    assert content_type(conn) =~ "application/json"
    assert json_body(conn) == %{"error" => "not found"}

    missing_user = call("/api/users/999")

    assert missing_user.status == 404
    assert json_body(missing_user) == json_body(conn)
    assert content_type(missing_user) == content_type(conn)
  end

  # The unmatched-route 404 is reached only after negotiation succeeds, and it
  # keeps its json body for other verbs and for paths outside /api as well.
  test "unmatched paths and verbs keep the json 404 body" do
    root =
      conn(:get, "/")
      |> MediaVersionApi.Router.call(@opts)

    assert root.status == 404
    assert content_type(root) =~ "application/json"
    assert json_body(root) == %{"error" => "not found"}

    posted =
      conn(:post, "/api/users/1")
      |> Plug.Conn.put_req_header("accept", "application/vnd.acme.v1+json")
      |> MediaVersionApi.Router.call(@opts)

    assert posted.status == 404
    assert content_type(posted) =~ "application/json"
    assert json_body(posted) == %{"error" => "not found"}
  end

  test "application/* resolves to the default version" do
    conn = call("/api/users/1", [{"accept", "application/*"}])

    assert conn.status == 200
    assert content_type(conn) =~ "v2"
    body = json_body(conn)
    assert body["first_name"] == "Alice"
    assert body["created_at"] == "2024-01-15T10:30:00Z"
    refute Map.has_key?(body, "name")
  end

  test "unrelated media type is ignored while a supported vendor range still wins" do
    conn =
      call("/api/users/1", [
        {"accept", "text/html;q=1.0, application/vnd.acme.v1+json;q=0.2"}
      ])

    assert conn.status == 200
    assert content_type(conn) =~ "application/vnd.acme.v1+json"
    assert json_body(conn)["name"] == "Alice Smith"
  end

  test "plug honours custom :supported and :default options" do
    opts = MediaVersionApi.Plugs.AcceptVersion.init(supported: ["v1"], default: "v1")

    absent = MediaVersionApi.Plugs.AcceptVersion.call(conn(:get, "/api/users/1"), opts)
    refute absent.halted
    assert absent.assigns[:api_version] == "v1"

    wildcard =
      conn(:get, "/api/users/1")
      |> Plug.Conn.put_req_header("accept", "*/*")
      |> MediaVersionApi.Plugs.AcceptVersion.call(opts)

    assert wildcard.assigns[:api_version] == "v1"

    rejected =
      conn(:get, "/api/users/1")
      |> Plug.Conn.put_req_header("accept", "application/vnd.acme.v2+json")
      |> MediaVersionApi.Plugs.AcceptVersion.call(opts)

    assert rejected.halted
    assert rejected.status == 406
    assert Jason.decode!(rejected.resp_body)["supported"] == ["v1"]
  end

  test "second user renders the full v2 shape from the store" do
    conn = call("/api/users/2", [{"accept", "application/vnd.acme.v2+json"}])

    assert conn.status == 200
    body = json_body(conn)
    assert body["first_name"] == "Bob"
    assert body["last_name"] == "Jones"
    assert body["email"] == "bob@example.com"
    assert body["created_at"] == "2024-06-20T14:00:00Z"
  end
end
```
