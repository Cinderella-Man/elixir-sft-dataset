  test "413 body reports the exact 5MB limit under max_bytes", %{opts: opts} do
    conn = post_upload(opts, "huge2.csv", String.duplicate("y", 5_242_881))
    assert conn.status == 413
    body = json_body(conn)
    assert body["error"] == "File too large"
    assert body["max_bytes"] == 5_242_880
    # rejection happens before acceptance: no record is created for it
    assert FileUpload.Store.list(:test_store) == []
  end