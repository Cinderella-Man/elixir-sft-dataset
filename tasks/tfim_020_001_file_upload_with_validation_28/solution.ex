  test "disallowed extension yields the exact documented error message", %{opts: opts} do
    conn = call_upload(opts, "archive.zip", "PK\x03\x04")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] == "File type not allowed. Only .csv and .json files are accepted"
  end