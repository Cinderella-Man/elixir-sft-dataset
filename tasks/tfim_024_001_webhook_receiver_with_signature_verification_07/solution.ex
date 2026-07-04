  test "duplicate event ID returns 200 with duplicate status", %{opts: opts, store: store} do
    payload = build_event("evt_010")
    sig = sign(payload, @secret)

    conn1 = post_webhook(opts, payload, [{"stripe-signature", sig}])
    assert conn1.status == 200
    assert json_body(conn1)["status"] == "received"

    conn2 = post_webhook(opts, payload, [{"stripe-signature", sig}])
    assert conn2.status == 200
    assert json_body(conn2)["status"] == "duplicate"

    # Only one record in the store
    events = WebhookReceiver.Store.all_events(store)
    matching = Enum.filter(events, &(&1.event_id == "evt_010"))
    assert length(matching) == 1
  end