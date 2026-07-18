  test "uploaded_at is a valid ISO 8601 string", %{opts: opts} do
    conn = call_upload(opts, "ts.csv", "a,b\n1,2\n")
    assert conn.status == 201

    body = json_body(conn)
    assert {:ok, _dt, _offset} = DateTime.from_iso8601(body["uploaded_at"])
  end