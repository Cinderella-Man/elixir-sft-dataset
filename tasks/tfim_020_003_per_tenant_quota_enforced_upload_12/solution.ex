  test "size limit enforced with 413", %{opts: opts} do
    big = String.duplicate("x", 5_242_881)
    conn = upload_conn(opts, "acct1", "huge.csv", big)
    assert conn.status == 413
  end