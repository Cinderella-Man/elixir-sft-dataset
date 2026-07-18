  test "uploading the same filename twice produces two distinct entries", %{opts: opts} do
    csv = "x,y\n1,2\n"
    conn1 = call_upload(opts, "dup.csv", csv)
    conn2 = call_upload(opts, "dup.csv", csv)

    assert conn1.status == 201
    assert conn2.status == 201

    body1 = json_body(conn1)
    body2 = json_body(conn2)

    assert body1["id"] != body2["id"]

    # Both files exist on disk
    assert File.exists?(Path.join(@upload_dir, body1["id"] <> ".csv"))
    assert File.exists?(Path.join(@upload_dir, body2["id"] <> ".csv"))
  end