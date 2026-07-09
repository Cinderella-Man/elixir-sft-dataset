  test "stripe provider verifies and stores", %{opts: opts, store: store} do
    payload = build_event("evt_s1")

    conn =
      post_webhook(opts, "stripe", payload, [{"stripe-signature", stripe_sig(payload, @stripe)}])

    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
    assert {:ok, event} = WebhookReceiver.Store.get_event(store, "stripe", "evt_s1")
    assert event.provider == "stripe"
    assert event.status == :pending
  end