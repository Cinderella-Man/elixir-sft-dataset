  test "empty header returns invalid_signature", %{opts: opts} do
    conn = post_webhook(opts, build_event("evt_004"), [{"stripe-signature", ""}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end