# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
    do: %{first_name: u.first_name, last_name: u.last_name, email: u.email, created_at: u.created_at}
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

  plug LifecycleApi.Plugs.ApiVersion, default: "v2"
  plug :match
  plug :dispatch

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

## Test harness — implement the `# TODO` test

```elixir
defmodule LifecycleApi.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test

  @opts LifecycleApi.Router.init([])

  defp call(path, headers \\ []) do
    conn =
      Enum.reduce(headers, conn(:get, path), fn {k, v}, c ->
        Plug.Conn.put_req_header(c, k, v)
      end)

    LifecycleApi.Router.call(conn, @opts)
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  defp content_type(conn) do
    {"content-type", ct} = List.keyfind(conn.resp_headers, "content-type", 0)
    ct
  end

  # -------------------------------------------------------
  # Active version
  # -------------------------------------------------------

  test "active v2 serves normally without deprecation headers" do
    conn = call("/api/users/1", [{"accept-version", "v2"}])

    assert conn.status == 200
    body = json_body(conn)
    assert body["first_name"] == "Alice"
    assert body["created_at"] == "2024-01-15T10:30:00Z"

    assert Plug.Conn.get_resp_header(conn, "deprecation") == []
    assert Plug.Conn.get_resp_header(conn, "sunset") == []
    assert Plug.Conn.get_resp_header(conn, "warning") == []
  end

  test "no header defaults to active v2" do
    conn = call("/api/users/1")
    assert conn.status == 200
    assert Map.has_key?(json_body(conn), "first_name")
    assert Plug.Conn.get_resp_header(conn, "deprecation") == []
  end

  # -------------------------------------------------------
  # Deprecated version
  # -------------------------------------------------------

  test "deprecated v1 serves the v1 shape but adds lifecycle headers" do
    conn = call("/api/users/1", [{"accept-version", "v1"}])

    assert conn.status == 200
    body = json_body(conn)
    assert body["name"] == "Alice Smith"
    refute Map.has_key?(body, "created_at")

    assert Plug.Conn.get_resp_header(conn, "deprecation") == ["true"]
    assert Plug.Conn.get_resp_header(conn, "sunset") == ["Sat, 01 Nov 2025 00:00:00 GMT"]

    [warning] = Plug.Conn.get_resp_header(conn, "warning")
    assert warning =~ "299"
    assert warning =~ "v1"
  end

  # -------------------------------------------------------
  # Retired version -> 410
  # -------------------------------------------------------

  test "retired v0 returns 410 Gone" do
    conn = call("/api/users/1", [{"accept-version", "v0"}])

    assert conn.status == 410
    body = json_body(conn)
    assert body["error"] =~ "retired"
    assert body["version"] == "v0"
    assert content_type(conn) =~ "application/json"
  end

  test "retired version halts before user lookup" do
    conn = call("/api/users/999", [{"accept-version", "v0"}])
    assert conn.status == 410
  end

  # -------------------------------------------------------
  # Unknown version -> 406
  # -------------------------------------------------------

  test "unknown version returns 406 with requestable versions only" do
    conn = call("/api/users/1", [{"accept-version", "v9"}])

    assert conn.status == 406
    body = json_body(conn)
    assert body["error"] =~ "unsupported"
    assert body["supported"] == ["v1", "v2"]
    refute "v0" in body["supported"]
  end

  test "supported list excludes the retired version in 410 responses too" do
    conn = call("/api/users/1", [{"accept-version", "v0"}])
    assert json_body(conn)["supported"] == ["v1", "v2"]
  end

  # -------------------------------------------------------
  # Not found (valid, non-retired version)
  # -------------------------------------------------------

  test "missing user with active version returns 404" do
    conn = call("/api/users/999", [{"accept-version", "v2"}])
    assert conn.status == 404
    assert json_body(conn)["error"] =~ "not found"
    assert content_type(conn) =~ "application/json"
  end

  test "missing user with deprecated version still returns 404 with lifecycle headers" do
    # TODO
  end

  # -------------------------------------------------------
  # Second user & content types
  # -------------------------------------------------------

  test "second user is correct in deprecated v1" do
    conn = call("/api/users/2", [{"accept-version", "v1"}])
    assert json_body(conn)["name"] == "Bob Jones"
  end

  test "success response is application/json" do
    conn = call("/api/users/1", [{"accept-version", "v2"}])
    assert content_type(conn) =~ "application/json"
  end

  test "unmatched route returns 404" do
    conn = call("/api/nope", [{"accept-version", "v2"}])
    assert conn.status == 404
  end
end
```
