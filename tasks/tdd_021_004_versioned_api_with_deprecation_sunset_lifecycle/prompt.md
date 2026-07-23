# The tests are the spec

Below is a complete, self-contained ExUnit suite. It is the only
specification you get: build the module (or modules) it exercises until
every test passes. Reach for nothing beyond what the tests themselves
require — the standard library and OTP unless the suite says otherwise.
House style applies (`@moduledoc`, `@doc` + `@spec` on the public API,
no compiler warnings).

## The test suite

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
    conn = call("/api/users/999", [{"accept-version", "v1"}])
    assert conn.status == 404
    assert Plug.Conn.get_resp_header(conn, "deprecation") == ["true"]
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

  test "ApiVersion initialised with no options falls back to the v2 default" do
    opts = LifecycleApi.Plugs.ApiVersion.init([])
    conn = LifecycleApi.Plugs.ApiVersion.call(conn(:get, "/api/users/1"), opts)

    assert conn.assigns[:api_version] == "v2"
    refute conn.halted
    assert Plug.Conn.get_resp_header(conn, "deprecation") == []
    assert Plug.Conn.get_resp_header(conn, "warning") == []
  end

  test "ApiVersion honours a configured :default when the header is absent" do
    opts = LifecycleApi.Plugs.ApiVersion.init(default: "v1")
    conn = LifecycleApi.Plugs.ApiVersion.call(conn(:get, "/api/users/1"), opts)

    assert conn.assigns[:api_version] == "v1"
    refute conn.halted
    assert Plug.Conn.get_resp_header(conn, "deprecation") == ["true"]
    assert Plug.Conn.get_resp_header(conn, "sunset") == ["Sat, 01 Nov 2025 00:00:00 GMT"]
  end

  test "unknown version 406 response is served as application/json" do
    conn = call("/api/users/1", [{"accept-version", "v9"}])

    assert conn.status == 406
    assert content_type(conn) =~ "application/json"
    assert conn.halted
  end

  test "deprecated v1 warning header matches the documented format exactly" do
    conn = call("/api/users/1", [{"accept-version", "v1"}])

    assert Plug.Conn.get_resp_header(conn, "warning") ==
             [~s(299 - "Deprecated API version v1")]
  end

  test "UserView v2 render returns exactly the four documented fields" do
    user = %{
      first_name: "Zed",
      last_name: "Quinn",
      email: "zed@example.com",
      created_at: "2025-02-02T09:00:00Z"
    }

    assert LifecycleApi.Views.UserView.render("v2", user) == %{
             first_name: "Zed",
             last_name: "Quinn",
             email: "zed@example.com",
             created_at: "2025-02-02T09:00:00Z"
           }
  end

  test "UserView v1 render returns exactly the joined name and the email" do
    user = %{
      first_name: "Zed",
      last_name: "Quinn",
      email: "zed@example.com",
      created_at: "2025-02-02T09:00:00Z"
    }

    assert LifecycleApi.Views.UserView.render("v1", user) ==
             %{name: "Zed Quinn", email: "zed@example.com"}
  end
end
```

Send back the implementation only — one file, no tests.
