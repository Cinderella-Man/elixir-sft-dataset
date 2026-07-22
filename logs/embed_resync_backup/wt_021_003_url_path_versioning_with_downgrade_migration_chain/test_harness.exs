defmodule PathVersionApi.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test

  @opts PathVersionApi.Router.init([])

  defp call(path) do
    PathVersionApi.Router.call(conn(:get, path), @opts)
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
end
