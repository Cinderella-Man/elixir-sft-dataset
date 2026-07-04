  test "duplicate is detected even with different payload bodies sharing the same id", %{
    opts: opts,
    store: store
  } do
    payload1 = build_event("evt_011", "charge.completed")
    sig1 = sign(payload1, @secret)

    conn1 = post_webhook(opts, payload1, [{"stripe-signature", sig1}])
    assert conn1.status == 200
    assert json_body(conn1)["status"] == "received"

    # Second delivery with same id but different type
    payload2 = build_event("evt_011", "charge.updated")
    sig2 = sign(payload2, @secret)

    conn2 = post_webhook(opts, payload2, [{"stripe-signature", sig2}])
    assert conn2.status == 200
    assert json_body(conn2)["status"] == "duplicate"

    # Original payload is preserved, not overwritten
    {:ok, event} = WebhookReceiver.Store.get_event(store, "evt_011")
    assert event.payload["type"] == "charge.completed"
  end