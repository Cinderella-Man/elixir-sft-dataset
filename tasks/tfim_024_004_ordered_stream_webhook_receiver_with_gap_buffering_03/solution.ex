  test "delivered events are marked :delivered", %{opts: opts, store: store} do
    assert deliver(opts, "e1", "s1", 1).status == 200
    [event] = WebhookReceiver.Store.delivered_events(store, "s1")
    assert event.status == :delivered
    assert event.event_id == "e1"
  end