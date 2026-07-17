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
    conn = call("/api/users/1", [{"accept", "*/*"}])
    assert conn.status == 200
    assert content_type(conn) =~ "v2"
    assert Map.has_key?(json_body(conn), "created_at")
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
