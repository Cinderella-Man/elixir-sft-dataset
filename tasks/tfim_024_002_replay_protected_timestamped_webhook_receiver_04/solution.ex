  test "expired (too old) timestamp returns timestamp_expired", %{opts: opts} do
    payload = build_event("evt_old")
    ts = @now - 1000
    conn = post_webhook(opts, payload, [{"stripe-signature", header(ts, payload, @secret)}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "timestamp_expired"
  end