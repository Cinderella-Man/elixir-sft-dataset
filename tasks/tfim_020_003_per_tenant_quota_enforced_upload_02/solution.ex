  test "valid upload under quota returns 201 with usage info", %{opts: opts} do
    conn = upload_conn(opts, "acct1", "a.csv", "name,age\nAlice,30\n")
    assert conn.status == 201
    body = json_body(conn)
    assert body["account_id"] == "acct1"
    assert body["quota_bytes"] == 1_000_000
    assert body["used_bytes"] == byte_size("name,age\nAlice,30\n")
    assert String.contains?(body["download_url"], body["id"])
  end