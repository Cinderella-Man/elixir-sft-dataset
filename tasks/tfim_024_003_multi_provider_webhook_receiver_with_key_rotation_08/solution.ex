  test "missing header returns invalid_signature", %{opts: opts} do
    conn = post_webhook(opts, "stripe", build_event("evt_s3"), [])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end