  test "future timestamp exactly at the tolerance edge is accepted, one past it expires",
       %{opts: opts} do
    edge = build_event("evt_future_edge")

    conn_edge =
      post_webhook(opts, edge, [{"stripe-signature", header(@now + 300, edge, @secret)}])

    assert conn_edge.status == 200
    assert json_body(conn_edge)["status"] == "received"

    past = build_event("evt_future_past")

    conn_past =
      post_webhook(opts, past, [{"stripe-signature", header(@now + 301, past, @secret)}])

    assert conn_past.status == 401
    assert json_body(conn_past)["error"] == "timestamp_expired"
  end