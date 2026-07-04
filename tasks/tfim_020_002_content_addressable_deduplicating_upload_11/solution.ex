  test "rejects malformed JSON with 422", %{opts: opts} do
    conn = call_upload(opts, "bad.json", "{not json")
    assert conn.status == 422
    assert json_body(conn)["error"] =~ "Invalid JSON"
  end