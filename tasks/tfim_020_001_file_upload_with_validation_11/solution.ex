  test "rejects an empty CSV with 422", %{opts: opts} do
    conn = call_upload(opts, "empty.csv", "")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "Invalid CSV"
  end