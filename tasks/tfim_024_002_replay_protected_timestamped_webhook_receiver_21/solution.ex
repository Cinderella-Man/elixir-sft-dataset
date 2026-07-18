  test "tolerance defaults to 300 seconds when the option is omitted", %{store: store} do
    opts = [secret: @secret, store: store, now: @now]

    inside = build_event("evt_default_in")
    hdr_in = header(@now - 300, inside, @secret)
    conn_in = post_webhook(opts, inside, [{"stripe-signature", hdr_in}])
    assert conn_in.status == 200
    assert json_body(conn_in)["status"] == "received"

    outside = build_event("evt_default_out")
    hdr_out = header(@now - 301, outside, @secret)
    conn_out = post_webhook(opts, outside, [{"stripe-signature", hdr_out}])
    assert conn_out.status == 401
    assert json_body(conn_out)["error"] == "timestamp_expired"
  end