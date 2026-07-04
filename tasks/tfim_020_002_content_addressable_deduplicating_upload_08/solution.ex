  test "rejects disallowed extension with 422", %{opts: opts} do
    conn = call_upload(opts, "notes.txt", "hello")
    assert conn.status == 422
    assert json_body(conn)["error"] =~ "not allowed"
  end