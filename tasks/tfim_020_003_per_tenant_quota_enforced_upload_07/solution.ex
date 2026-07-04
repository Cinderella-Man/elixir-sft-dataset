  test "missing account header returns 400 on POST", %{opts: opts} do
    conn = upload_conn(opts, nil, "a.csv", "a,b\n1,2\n")
    assert conn.status == 400
    assert json_body(conn)["error"] =~ "Missing account"
  end