  test "duplicate within provider returns duplicate", %{opts: opts, store: store} do
    payload = build_event("evt_dup")
    sig = stripe_sig(payload, @stripe)

    c1 = post_webhook(opts, "stripe", payload, [{"stripe-signature", sig}])
    c2 = post_webhook(opts, "stripe", payload, [{"stripe-signature", sig}])

    assert json_body(c1)["status"] == "received"
    assert json_body(c2)["status"] == "duplicate"

    events = WebhookReceiver.Store.all_events(store)
    assert length(Enum.filter(events, &(&1.event_id == "evt_dup"))) == 1
  end