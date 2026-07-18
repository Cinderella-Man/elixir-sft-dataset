  test "expired timestamp with a bad signature reports timestamp_expired", %{opts: opts} do
    payload = build_event("evt_order")
    ts = @now - 1000
    hdr = header(ts, payload, "wrong_secret_entirely")
    conn = post_webhook(opts, payload, [{"stripe-signature", hdr}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "timestamp_expired"
  end