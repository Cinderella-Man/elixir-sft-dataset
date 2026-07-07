  test "new CSV upload returns 201 with sha256 id, deduplicated=false", %{opts: opts} do
    conn = call_upload(opts, "people.csv", "name,age\nAlice,30\n")
    assert conn.status == 201
    body = json_body(conn)
    assert String.length(body["id"]) == 64
    assert body["id"] =~ ~r/\A[0-9a-f]{64}\z/
    assert body["deduplicated"] == false
    assert body["upload_count"] == 1
    assert body["original_name"] == "people.csv"
    assert String.contains?(body["download_url"], body["id"])
  end