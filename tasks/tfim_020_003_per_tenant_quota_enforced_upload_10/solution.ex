  test "delete of unknown id returns 404", %{opts: opts} do
    conn = delete_conn(opts, "acct1", "does-not-exist")
    assert conn.status == 404
    assert json_body(conn)["error"] =~ "Not found"
  end