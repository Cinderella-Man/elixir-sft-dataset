  test "rejects .txt files with 422", %{opts: opts} do
    conn = call_upload(opts, "notes.txt", "some text content")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "not allowed"
  end