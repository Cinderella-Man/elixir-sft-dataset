  test "download URL contains the base_url and file id", %{opts: opts} do
    conn = call_upload(opts, "dl.json", Jason.encode!(%{}))
    assert conn.status == 201

    body = json_body(conn)
    assert String.starts_with?(body["download_url"], "http://localhost:4000")
    assert String.contains?(body["download_url"], body["id"])
  end