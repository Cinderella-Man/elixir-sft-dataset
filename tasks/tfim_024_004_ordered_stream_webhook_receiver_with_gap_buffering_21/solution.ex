  test "drain stops at the first gap and leaves later events buffered", %{
    opts: opts,
    store: store
  } do
    assert deliver(opts, "e1", "s1", 1).status == 200
    assert deliver(opts, "e3", "s1", 3).status == 202
    assert deliver(opts, "e5", "s1", 5).status == 202

    assert json_body(deliver(opts, "e2", "s1", 2))["status"] == "received"

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 3
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == [5]

    events = WebhookReceiver.Store.delivered_events(store, "s1")
    assert Enum.map(events, & &1.sequence) == [1, 2, 3]
    assert Enum.map(events, & &1.status) == [:delivered, :delivered, :delivered]
  end