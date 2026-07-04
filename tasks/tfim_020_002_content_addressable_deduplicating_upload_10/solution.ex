  test "rejects invalid CSV with 422", %{opts: opts} do
    conn = call_upload(opts, "bad.csv", "justonevalue")
    assert conn.status == 422
    assert json_body(conn)["error"] =~ "Invalid CSV"
  end