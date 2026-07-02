  test "file is actually persisted to disk", %{opts: opts} do
    csv_content = "col1,col2\nval1,val2\n"
    conn = call_upload(opts, "disk_check.csv", csv_content)

    assert conn.status == 201
    body = json_body(conn)

    # The file should exist in the upload dir with the UUID-based name
    expected_path = Path.join(@upload_dir, body["id"] <> ".csv")
    assert File.exists?(expected_path)
    assert File.read!(expected_path) == csv_content
  end