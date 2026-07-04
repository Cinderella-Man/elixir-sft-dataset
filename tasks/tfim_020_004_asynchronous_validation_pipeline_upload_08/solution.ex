  test "file is persisted to disk immediately (even while pending)", %{opts: opts} do
    conn = post_upload(opts, "disk.csv", "col1,col2\nv1,v2\n")
    id = json_body(conn)["id"]
    # copy is synchronous, so the file exists right after the request returns
    path = Path.join(@upload_dir, id <> ".csv")
    assert File.exists?(path)
    assert File.read!(path) == "col1,col2\nv1,v2\n"
  end