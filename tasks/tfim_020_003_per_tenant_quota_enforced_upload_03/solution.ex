  test "usage accumulates across uploads for the same account", %{opts: opts} do
    upload_conn(opts, "acct1", "a.csv", "a,b\n1,2\n")
    conn = upload_conn(opts, "acct1", "b.csv", "c,d\n3,4\n")
    assert conn.status == 201
    assert json_body(conn)["used_bytes"] == 16
    assert FileUpload.Store.usage(:big_store, "acct1") == 16
  end