  test "rejects empty JSON file with 422", %{opts: opts} do
    conn = call_upload(opts, "empty.json", "")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "Invalid JSON"
  end