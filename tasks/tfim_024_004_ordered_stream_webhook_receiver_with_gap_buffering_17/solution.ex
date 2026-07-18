  test "drained buffered events are marked :delivered, not :pending", %{
    opts: opts,
    store: store
  } do
    assert deliver(opts, "e1", "s1", 1).status == 200
    assert deliver(opts, "e3", "s1", 3).status == 202
    assert deliver(opts, "e4", "s1", 4).status == 202
    assert deliver(opts, "e2", "s1", 2).status == 200

    events = WebhookReceiver.Store.delivered_events(store, "s1")
    assert Enum.map(events, & &1.sequence) == [1, 2, 3, 4]
    assert Enum.map(events, & &1.status) == [:delivered, :delivered, :delivered, :delivered]
  end