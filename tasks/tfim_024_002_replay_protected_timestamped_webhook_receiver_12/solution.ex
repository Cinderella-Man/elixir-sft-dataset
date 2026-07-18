  test "duplicate delivery returns duplicate", %{opts: opts, store: store} do
    payload = build_event("evt_010")
    hdr = header(@now, payload, @secret)

    conn1 = post_webhook(opts, payload, [{"stripe-signature", hdr}])
    assert json_body(conn1)["status"] == "received"

    conn2 = post_webhook(opts, payload, [{"stripe-signature", hdr}])
    assert conn2.status == 200
    assert json_body(conn2)["status"] == "duplicate"

    events = WebhookReceiver.Store.all_events(store)
    assert length(Enum.filter(events, &(&1.event_id == "evt_010"))) == 1
  end