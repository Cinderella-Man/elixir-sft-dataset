  test "rejects a CSV with only a single value (no columns)", %{opts: opts} do
    conn = call_upload(opts, "single.csv", "justonevalue")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "Invalid CSV"
  end