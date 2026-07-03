  test "POST returns 202 pending synchronously with a status_url", %{opts: opts} do
    conn = post_upload(opts, "people.csv", "name,age\nAlice,30\n")
    assert conn.status == 202
    body = json_body(conn)
    assert body["status"] == "pending"
    assert is_binary(body["id"])
    assert String.length(body["id"]) == 36
    assert String.contains?(body["status_url"], body["id"])
    assert body["original_name"] == "people.csv"
    assert {:ok, _dt, _} = DateTime.from_iso8601(body["uploaded_at"])
  end