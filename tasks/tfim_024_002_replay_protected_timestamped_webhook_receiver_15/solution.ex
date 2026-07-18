  test "now option accepts a 0-arity function", %{store: store} do
    opts = [secret: @secret, store: store, now: fn -> @now end]
    payload = build_event("evt_fn")
    conn = post_webhook(opts, payload, [{"stripe-signature", header(@now, payload, @secret)}])
    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
  end