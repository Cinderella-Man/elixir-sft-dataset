  test "single-value single-line CSV yields the exact documented error message", %{opts: opts} do
    conn = call_upload(opts, "lonely.csv", "onlyvalue\n")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] == "Invalid CSV: file must contain a header row with multiple columns"
  end