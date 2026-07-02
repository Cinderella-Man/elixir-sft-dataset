  test "uploads a valid JSON file and returns 201 with metadata", %{opts: opts} do
    json_content = Jason.encode!(%{"users" => [%{"name" => "Alice"}, %{"name" => "Bob"}]})
    conn = call_upload(opts, "data.json", json_content)

    assert conn.status == 201

    body = json_body(conn)
    assert body["original_name"] == "data.json"
    assert body["size"] == byte_size(json_content)
    assert body["content_type"] == "application/json"
    assert is_binary(body["id"])
    assert is_binary(body["uploaded_at"])
    assert is_binary(body["download_url"])
  end