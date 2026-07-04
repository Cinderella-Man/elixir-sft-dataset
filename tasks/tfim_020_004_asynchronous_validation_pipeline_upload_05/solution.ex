  test "invalid CSV content transitions to invalid with an error", %{opts: opts} do
    conn = post_upload(opts, "bad.csv", "singlevalue")
    assert conn.status == 202
    id = json_body(conn)["id"]

    rec = await_settled(:test_store, id)
    assert rec.status == :invalid

    body = json_body(get_status(opts, id))
    assert body["status"] == "invalid"
    assert body["error"] =~ "Invalid CSV"
    refute Map.has_key?(body, "download_url")
  end