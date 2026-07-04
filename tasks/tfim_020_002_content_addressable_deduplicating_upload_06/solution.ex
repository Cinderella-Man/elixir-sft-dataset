  test "file is persisted to disk under the hash name", %{opts: opts} do
    conn = call_upload(opts, "disk.csv", "col1,col2\nv1,v2\n")
    assert conn.status == 201
    body = json_body(conn)
    path = Path.join(@upload_dir, body["id"] <> ".csv")
    assert File.exists?(path)
    assert File.read!(path) == "col1,col2\nv1,v2\n"
  end