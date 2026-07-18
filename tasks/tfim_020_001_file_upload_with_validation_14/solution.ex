  test "rejects malformed JSON with 422 and descriptive error", %{opts: opts} do
    conn = call_upload(opts, "bad.json", "{invalid json content")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "Invalid JSON"
  end