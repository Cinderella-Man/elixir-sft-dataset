  test "uploads a valid CSV and returns 201 with metadata", %{opts: opts} do
    csv_content = "name,age,email\nAlice,30,alice@example.com\nBob,25,bob@test.com\n"
    conn = call_upload(opts, "people.csv", csv_content)

    assert conn.status == 201

    body = json_body(conn)
    assert body["original_name"] == "people.csv"
    assert body["size"] == byte_size(csv_content)
    assert body["content_type"] == "text/csv"
    assert is_binary(body["id"])
    # UUID v4 length
    assert String.length(body["id"]) == 36
    assert is_binary(body["uploaded_at"])
    assert String.contains?(body["download_url"], body["id"])
  end