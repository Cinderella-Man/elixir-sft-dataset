  test "wrong secret returns invalid_signature", %{opts: opts} do
    payload = build_event("evt_002")
    conn = post_webhook(opts, payload, [{"stripe-signature", header(@now, payload, "nope")}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end