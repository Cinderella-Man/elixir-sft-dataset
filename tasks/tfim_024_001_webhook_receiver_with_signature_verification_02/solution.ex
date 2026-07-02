  test "returns 200 and stores event when signature is valid", %{opts: opts, store: store} do
    payload = build_event("evt_001")
    sig = sign(payload, @secret)

    conn = post_webhook(opts, payload, [{"stripe-signature", sig}])

    assert conn.status == 200
    assert json_body(conn)["status"] == "received"

    # Verify the event was persisted
    assert {:ok, event} = WebhookReceiver.Store.get_event(store, "evt_001")
    assert event.event_id == "evt_001"
    assert event.status == :pending
    assert event.payload["type"] == "charge.completed"
  end