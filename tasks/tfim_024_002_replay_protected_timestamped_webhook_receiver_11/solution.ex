  test "non-integer timestamp returns invalid_signature", %{opts: opts} do
    payload = build_event("evt_ts")
    hdr = "t=abc,v1=#{v1(@now, payload, @secret)}"
    conn = post_webhook(opts, payload, [{"stripe-signature", hdr}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end