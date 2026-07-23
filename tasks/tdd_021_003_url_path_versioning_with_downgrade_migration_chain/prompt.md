# Implement to green

Treat the ExUnit suite below as the full requirements document. Write the
code under test so the whole suite passes. Dependencies: only what the
tests already use (the standard library and OTP otherwise). Style:
`@moduledoc`, `@doc` + `@spec` on the public API, warning-free compile.

## The test suite

```elixir
defmodule PathVersionApi.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test

  @opts PathVersionApi.Router.init([])

  defp call(path) do
    PathVersionApi.Router.call(conn(:get, path), @opts)
  end

  defp call(method, path) do
    PathVersionApi.Router.call(conn(method, path), @opts)
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  defp content_type(conn) do
    {"content-type", ct} = List.keyfind(conn.resp_headers, "content-type", 0)
    ct
  end

  # -------------------------------------------------------
  # v3 canonical shape (nested name + country)
  # -------------------------------------------------------

  test "v3 returns the canonical nested representation" do
    conn = call("/api/v3/users/1")

    assert conn.status == 200
    body = json_body(conn)

    assert body["id"] == "1"
    assert body["name"] == %{"first" => "Alice", "last" => "Smith"}
    assert body["email"] == "alice@example.com"
    assert body["created_at"] == "2024-01-15T10:30:00Z"
    assert body["country"] == "US"
  end

  # -------------------------------------------------------
  # v2 downgrade (flatten name, drop country)
  # -------------------------------------------------------

  test "v2 flattens name and drops country" do
    conn = call("/api/v2/users/1")

    assert conn.status == 200
    body = json_body(conn)

    assert body["id"] == "1"
    assert body["first_name"] == "Alice"
    assert body["last_name"] == "Smith"
    assert body["created_at"] == "2024-01-15T10:30:00Z"
    refute Map.has_key?(body, "country")
    refute Map.has_key?(body, "name")
  end

  # -------------------------------------------------------
  # v1 downgrade (combine name, drop created_at)
  # -------------------------------------------------------

  test "v1 combines the name and drops created_at and country" do
    conn = call("/api/v1/users/1")

    assert conn.status == 200
    body = json_body(conn)

    assert body["id"] == "1"
    assert body["name"] == "Alice Smith"
    assert body["email"] == "alice@example.com"
    refute Map.has_key?(body, "first_name")
    refute Map.has_key?(body, "last_name")
    refute Map.has_key?(body, "created_at")
    refute Map.has_key?(body, "country")
  end

  test "each version yields a distinct key set" do
    keys = fn v -> "/api/#{v}/users/1" |> call() |> json_body() |> Map.keys() |> Enum.sort() end

    assert keys.("v1") == ["email", "id", "name"]
    assert keys.("v2") == ["created_at", "email", "first_name", "id", "last_name"]
    assert keys.("v3") == ["country", "created_at", "email", "id", "name"]
  end

  # -------------------------------------------------------
  # Unsupported version -> 400 (before user lookup)
  # -------------------------------------------------------

  test "unsupported path version returns 400" do
    conn = call("/api/v9/users/1")

    assert conn.status == 400
    body = json_body(conn)
    assert body["error"] =~ "unsupported"
    assert body["supported"] == ["v1", "v2", "v3"]
  end

  test "unsupported version returns 400 even for a missing user" do
    conn = call("/api/v9/users/999")
    assert conn.status == 400
  end

  # -------------------------------------------------------
  # Not found
  # -------------------------------------------------------

  test "valid version + missing user returns 404" do
    conn = call("/api/v2/users/999")
    assert conn.status == 404
    assert json_body(conn)["error"] =~ "not found"
  end

  # -------------------------------------------------------
  # Second user & content type
  # -------------------------------------------------------

  test "second user resolves through the chain in v1" do
    conn = call("/api/v1/users/2")
    body = json_body(conn)
    assert body["name"] == "Bob Jones"
    assert body["email"] == "bob@example.com"
  end

  test "second user has its own country in v3" do
    conn = call("/api/v3/users/2")
    assert json_body(conn)["country"] == "GB"
  end

  test "all responses are application/json" do
    for path <- ["/api/v1/users/1", "/api/v2/users/999", "/api/v9/users/1"] do
      assert content_type(call(path)) =~ "application/json"
    end
  end

  # -------------------------------------------------------
  # Migrations module used directly
  # -------------------------------------------------------

  test "supported/0 lists versions ascending" do
    assert PathVersionApi.Migrations.supported() == ["v1", "v2", "v3"]
  end

  test "render/3 is a pure downgrade of the canonical document" do
    user = %{
      first_name: "Zoe",
      last_name: "Lin",
      email: "zoe@example.com",
      created_at: "2023-03-03T00:00:00Z",
      country: "SG"
    }

    assert PathVersionApi.Migrations.render("v1", "42", user) ==
             %{id: "42", name: "Zoe Lin", email: "zoe@example.com"}
  end

  test "unmatched route returns 404" do
    conn = call("/api/v1/widgets/1")
    assert conn.status == 404
  end

  test "400 body carries the exact unsupported-version error payload" do
    conn = call("/api/v4/users/1")

    assert conn.status == 400

    assert json_body(conn) == %{
             "error" => "unsupported version",
             "supported" => ["v1", "v2", "v3"]
           }
  end

  test "404 body for a missing user is exactly the not-found payload" do
    for version <- ["v1", "v2", "v3"] do
      conn = call("/api/#{version}/users/nope")

      assert conn.status == 404
      assert json_body(conn) == %{"error" => "not found"}
    end
  end

  test "render/3 for v3 returns the canonical document verbatim with no steps applied" do
    user = %{
      first_name: "Zoe",
      last_name: "Lin",
      email: "zoe@example.com",
      created_at: "2023-03-03T00:00:00Z",
      country: "SG"
    }

    assert PathVersionApi.Migrations.render("v3", "42", user) ==
             %{
               id: "42",
               name: %{first: "Zoe", last: "Lin"},
               email: "zoe@example.com",
               created_at: "2023-03-03T00:00:00Z",
               country: "SG"
             }
  end

  test "render/3 for v2 applies exactly the one downgrade step" do
    user = %{
      first_name: "Zoe",
      last_name: "Lin",
      email: "zoe@example.com",
      created_at: "2023-03-03T00:00:00Z",
      country: "SG"
    }

    assert PathVersionApi.Migrations.render("v2", "42", user) ==
             %{
               id: "42",
               first_name: "Zoe",
               last_name: "Lin",
               email: "zoe@example.com",
               created_at: "2023-03-03T00:00:00Z"
             }
  end

  test "the unmatched-route response is also json encoded" do
    conn = call("/api/v1/widgets/1")

    assert content_type(conn) =~ "application/json"
    assert json_body(conn) == %{"error" => "not found"}
  end

  test "every supported version is renderable and no other version is accepted" do
    for version <- PathVersionApi.Migrations.supported() do
      assert call("/api/#{version}/users/1").status == 200
    end

    # Note: an empty version segment is not testable here — Plug collapses
    # "/api//users/1" to path_info ["api", "users", "1"], which is a different
    # route entirely rather than a request carrying an empty version.
    for version <- ["V1", "v0", "1", "v10", "v3.1", "v"] do
      refute version in PathVersionApi.Migrations.supported()
      assert call("/api/#{version}/users/1").status == 400
    end
  end

  # -------------------------------------------------------
  # Only GET matches the user route; other methods are 404
  # -------------------------------------------------------

  test "non-GET methods on the user path return the not-found response" do
    for method <- [:post, :put, :patch, :delete] do
      conn = call(method, "/api/v1/users/1")

      assert conn.status == 404
      assert json_body(conn) == %{"error" => "not found"}
      assert content_type(conn) =~ "application/json"
    end
  end

  test "every supported version rejects a non-GET request with 404 rather than a body" do
    for version <- ["v1", "v2", "v3"] do
      conn = call(:post, "/api/#{version}/users/1")

      assert conn.status == 404
      assert json_body(conn) == %{"error" => "not found"}
    end
  end

  test "a non-GET request with an unsupported version is 404, not the 400 version error" do
    conn = call(:delete, "/api/v9/users/1")

    assert conn.status == 404
    assert json_body(conn) == %{"error" => "not found"}
  end
end
```

Deliverable: the module(s) alone in a single file — not the tests.
