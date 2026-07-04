  test "rejects files with no extension with 422", %{opts: opts} do
    conn = call_upload(opts, "Makefile", "all:\n\techo hello")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "not allowed"
  end