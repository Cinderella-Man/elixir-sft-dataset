  test "delete by wrong account is forbidden", %{opts: opts} do
    up = upload_conn(opts, "owner", "a.csv", "a,b\n1,2\n")
    id = json_body(up)["id"]
    conn = delete_conn(opts, "intruder", id)
    assert conn.status == 403
    assert json_body(conn)["error"] =~ "Forbidden"
    # still present
    assert File.exists?(Path.join(@upload_dir, id <> ".csv"))
  end