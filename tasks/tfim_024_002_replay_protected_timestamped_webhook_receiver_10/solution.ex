  test "malformed header (no v1 element) returns invalid_signature", %{opts: opts} do
    conn = post_webhook(opts, build_event("evt_hdr"), [{"stripe-signature", "t=#{@now}"}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end