  test "Store.get_event/3 returns :error for an unstored provider/id pair", %{
    opts: opts,
    store: store
  } do
    assert :error = WebhookReceiver.Store.get_event(store, "stripe", "never_stored")
    assert WebhookReceiver.Store.all_events(store) == []

    payload = build_event("evt_only")
    post_webhook(opts, "stripe", payload, [{"stripe-signature", stripe_sig(payload, @stripe)}])

    assert :error = WebhookReceiver.Store.get_event(store, "github", "evt_only")
    assert :error = WebhookReceiver.Store.get_event(store, "stripe", "evt_other")
  end