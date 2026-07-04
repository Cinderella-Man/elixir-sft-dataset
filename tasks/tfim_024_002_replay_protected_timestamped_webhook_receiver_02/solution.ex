  test "valid, in-window signature stores event", %{opts: opts, store: store} do
    payload = build_event("evt_001")
    conn = post_webhook(opts, payload, [{"stripe-signature", header(@now, payload, @secret)}])

    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
    assert {:ok, event} = WebhookReceiver.Store.get_event(store, "evt_001")
    assert event.event_id == "evt_001"
    assert event.status == :pending
    assert event.payload["type"] == "charge.completed"
  end