  test "rejects .exe files with 422", %{opts: opts} do
    conn = call_upload(opts, "malware.exe", "MZ\x90\x00")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "not allowed"
  end