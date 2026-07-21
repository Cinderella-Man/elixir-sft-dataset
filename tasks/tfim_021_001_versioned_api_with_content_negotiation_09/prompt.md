# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
<file path="lib/versioned_api/views/user_view.ex">
defmodule VersionedApi.Views.UserView do
  @moduledoc "Renders a user map per API version: v1 is a flat name, v2 is structured."

  @doc ~s|Renders `u` for API `version` ("v1" or "v2") as a plain map.|
  @spec render(String.t(), map()) :: map()
  def render("v1", u), do: %{name: u.first_name <> " " <> u.last_name, email: u.email}

  def render("v2", u) do
    %{first_name: u.first_name, last_name: u.last_name, email: u.email, created_at: u.created_at}
  end
end
</file>
<file path="lib/versioned_api/plugs/api_version.ex">
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
</file>
<file path="lib/versioned_api/router.ex">
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
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end
end
</file>
```

## Test harness — implement the `# TODO` test

```elixir
defmodule VersionedApi.RouterTest do
  use ExUnit.Case, async: true
  import Plug.Test

  @opts VersionedApi.Router.init([])

  # -------------------------------------------------------
  # Helper
  # -------------------------------------------------------

  defp call(method, path, headers \\ []) do
    conn =
      Enum.reduce(headers, conn(method, path), fn {key, val}, c ->
        Plug.Conn.put_req_header(c, key, val)
      end)

    VersionedApi.Router.call(conn, @opts)
  end

  defp json_body(conn) do
    Jason.decode!(conn.resp_body)
  end

  # -------------------------------------------------------
  # Version 1 responses
  # -------------------------------------------------------

  test "v1 returns {name, email} shape" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v1"}])

    assert conn.status == 200
    body = json_body(conn)

    assert Map.has_key?(body, "name")
    assert Map.has_key?(body, "email")

    # v1 must NOT contain v2-only fields
    refute Map.has_key?(body, "first_name")
    refute Map.has_key?(body, "last_name")
    refute Map.has_key?(body, "created_at")
  end

  test "v1 name is first_name + last_name combined" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v1"}])
    body = json_body(conn)

    assert body["name"] == "Alice Smith"
    assert body["email"] == "alice@example.com"
  end

  # -------------------------------------------------------
  # Version 2 responses
  # -------------------------------------------------------

  test "v2 returns {first_name, last_name, email, created_at} shape" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v2"}])

    assert conn.status == 200
    body = json_body(conn)

    assert Map.has_key?(body, "first_name")
    assert Map.has_key?(body, "last_name")
    assert Map.has_key?(body, "email")
    assert Map.has_key?(body, "created_at")

    # v2 must NOT contain the v1 combined name field
    refute Map.has_key?(body, "name")
  end

  test "v2 returns correct field values" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v2"}])
    body = json_body(conn)

    assert body["first_name"] == "Alice"
    assert body["last_name"] == "Smith"
    assert body["email"] == "alice@example.com"
    assert body["created_at"] == "2024-01-15T10:30:00Z"
  end

  # -------------------------------------------------------
  # Default version (no header)
  # -------------------------------------------------------

  test "no Accept-Version header defaults to latest (v2)" do
    conn = call(:get, "/api/users/1")

    assert conn.status == 200
    body = json_body(conn)

    # Should match v2 shape
    assert Map.has_key?(body, "first_name")
    assert Map.has_key?(body, "last_name")
    assert Map.has_key?(body, "email")
    assert Map.has_key?(body, "created_at")
    refute Map.has_key?(body, "name")
  end

  test "default response is identical to explicit v2 request" do
    conn_default = call(:get, "/api/users/2")
    conn_v2 = call(:get, "/api/users/2", [{"accept-version", "v2"}])

    assert json_body(conn_default) == json_body(conn_v2)
  end

  # -------------------------------------------------------
  # Unsupported version → 406
  # -------------------------------------------------------

  test "unsupported version returns 406 Not Acceptable" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v3"}])

    assert conn.status == 406
    body = json_body(conn)

    assert body["error"] =~ "unsupported"
  end

  test "406 response includes list of supported versions" do
    # TODO
  end

  test "random gibberish version returns 406" do
    conn = call(:get, "/api/users/1", [{"accept-version", "banana"}])

    assert conn.status == 406
  end

  # -------------------------------------------------------
  # User not found
  # -------------------------------------------------------

  test "returns 404 for a non-existent user with v1" do
    conn = call(:get, "/api/users/999", [{"accept-version", "v1"}])

    assert conn.status == 404
    body = json_body(conn)
    assert body["error"] =~ "not found"
  end

  test "returns 404 for a non-existent user with v2" do
    conn = call(:get, "/api/users/999", [{"accept-version", "v2"}])

    assert conn.status == 404
  end

  test "returns 404 for a non-existent user with default version" do
    conn = call(:get, "/api/users/999")

    assert conn.status == 404
  end

  # -------------------------------------------------------
  # Content-Type
  # -------------------------------------------------------

  test "all success responses have application/json content type" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v1"}])

    assert {"content-type", content_type} =
             List.keyfind(conn.resp_headers, "content-type", 0)

    assert content_type =~ "application/json"
  end

  test "406 response has application/json content type" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v99"}])

    assert {"content-type", content_type} =
             List.keyfind(conn.resp_headers, "content-type", 0)

    assert content_type =~ "application/json"
  end

  test "404 response has application/json content type" do
    conn = call(:get, "/api/users/999")

    assert {"content-type", content_type} =
             List.keyfind(conn.resp_headers, "content-type", 0)

    assert content_type =~ "application/json"
  end

  # -------------------------------------------------------
  # Version shapes differ
  # -------------------------------------------------------

  test "v1 and v2 responses for the same user have different keys" do
    conn_v1 = call(:get, "/api/users/1", [{"accept-version", "v1"}])
    conn_v2 = call(:get, "/api/users/1", [{"accept-version", "v2"}])

    keys_v1 = json_body(conn_v1) |> Map.keys() |> Enum.sort()
    keys_v2 = json_body(conn_v2) |> Map.keys() |> Enum.sort()

    refute keys_v1 == keys_v2
  end

  # -------------------------------------------------------
  # Second user (data integrity)
  # -------------------------------------------------------

  test "second user is also accessible and correct in v2" do
    conn = call(:get, "/api/users/2", [{"accept-version", "v2"}])

    assert conn.status == 200
    body = json_body(conn)

    assert body["first_name"] == "Bob"
    assert body["last_name"] == "Jones"
    assert body["email"] == "bob@example.com"
    assert body["created_at"] == "2024-06-20T14:00:00Z"
  end

  test "second user is correct in v1" do
    conn = call(:get, "/api/users/2", [{"accept-version", "v1"}])

    assert conn.status == 200
    body = json_body(conn)

    assert body["name"] == "Bob Jones"
    assert body["email"] == "bob@example.com"
  end

  # -------------------------------------------------------
  # Version plug halts before route matching
  # -------------------------------------------------------

  test "unsupported version returns 406 even for non-existent user" do
    conn = call(:get, "/api/users/999", [{"accept-version", "v3"}])

    # The version plug should halt before the router tries to look up the user
    assert conn.status == 406
  end

  # -------------------------------------------------------
  # Unmatched routes
  # -------------------------------------------------------

  test "unmatched route returns 404" do
    conn = call(:get, "/api/nonexistent")

    assert conn.status == 404
  end

  # -------------------------------------------------------
  # The version plug is driven by its own :supported/:default
  # options, not by a fixed built-in version list
  # -------------------------------------------------------

  defp call_version_plug(headers, opts) do
    conn =
      Enum.reduce(headers, conn(:get, "/api/users/1"), fn {key, val}, c ->
        Plug.Conn.put_req_header(c, key, val)
      end)

    VersionedApi.Plugs.ApiVersion.call(conn, VersionedApi.Plugs.ApiVersion.init(opts))
  end

  test "plug assigns the configured :default version when no header is present" do
    opts = [supported: ["v1", "v2", "v3"], default: "v3"]
    conn = call_version_plug([], opts)

    assert conn.assigns[:api_version] == "v3"
    refute conn.halted
  end

  test "plug accepts a version that only the configured :supported list allows" do
    opts = [supported: ["v3", "v4"], default: "v3"]
    conn = call_version_plug([{"accept-version", "v4"}], opts)

    assert conn.assigns[:api_version] == "v4"
    refute conn.halted
  end

  test "plug halts with 406 for a version absent from the configured :supported list" do
    opts = [supported: ["v3", "v4"], default: "v3"]
    conn = call_version_plug([{"accept-version", "v1"}], opts)

    assert conn.status == 406
    assert conn.halted

    body = json_body(conn)
    assert body["error"] =~ "unsupported"
    # The 406 body echoes the versions this plug was configured with
    assert body["supported"] == ["v3", "v4"]
  end
end
```
