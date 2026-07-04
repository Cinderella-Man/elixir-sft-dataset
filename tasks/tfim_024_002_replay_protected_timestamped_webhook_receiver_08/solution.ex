  test "missing header returns invalid_signature", %{opts: opts} do
    conn = post_webhook(opts, build_event("evt_003"), [])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end