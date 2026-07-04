  test "rejects files larger than 5MB with 413", %{opts: opts} do
    # Create content just over 5MB
    big_content = String.duplicate("x", 5_242_881)
    conn = call_upload(opts, "huge.csv", big_content)

    assert conn.status == 413
    body = json_body(conn)
    assert body["error"] =~ "too large" or body["error"] =~ "Too large"
  end