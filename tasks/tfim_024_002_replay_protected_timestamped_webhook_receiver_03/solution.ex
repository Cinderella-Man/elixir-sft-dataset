  test "signature just inside the tolerance window is accepted", %{opts: opts} do
    payload = build_event("evt_edge")
    ts = @now - 300
    conn = post_webhook(opts, payload, [{"stripe-signature", header(ts, payload, @secret)}])
    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
  end