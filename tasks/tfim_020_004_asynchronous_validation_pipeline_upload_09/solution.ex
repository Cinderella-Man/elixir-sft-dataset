  test "oversize file is rejected synchronously with 413", %{opts: opts} do
    big = String.duplicate("x", 5_242_881)
    conn = post_upload(opts, "huge.csv", big)
    assert conn.status == 413
    assert json_body(conn)["error"] =~ "too large"
  end