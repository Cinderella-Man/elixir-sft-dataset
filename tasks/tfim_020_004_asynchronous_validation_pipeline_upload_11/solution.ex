  test "GET on unknown id returns 404", %{opts: opts} do
    conn = get_status(opts, "no-such-id")
    assert conn.status == 404
    assert json_body(conn)["error"] =~ "Not found"
  end