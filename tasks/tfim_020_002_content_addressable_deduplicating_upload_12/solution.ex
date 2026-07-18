  test "rejects files larger than 5MB with 413", %{opts: opts} do
    big = String.duplicate("x", 5_242_881)
    conn = call_upload(opts, "huge.csv", big)
    assert conn.status == 413
    assert json_body(conn)["error"] =~ "too large"
  end