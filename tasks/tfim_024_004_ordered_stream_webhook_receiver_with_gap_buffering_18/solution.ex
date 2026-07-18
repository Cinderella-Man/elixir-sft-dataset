  test "events drained via Store.deliver/2 are marked :delivered", %{store: store} do
    e1 = %{event_id: "d1", stream_id: "z", sequence: 1, payload: %{}, status: :pending}
    e2 = %{event_id: "d2", stream_id: "z", sequence: 2, payload: %{}, status: :pending}

    assert {:ok, :buffered} = WebhookReceiver.Store.deliver(store, e2)
    assert {:ok, :received} = WebhookReceiver.Store.deliver(store, e1)

    events = WebhookReceiver.Store.delivered_events(store, "z")
    assert Enum.map(events, & &1.event_id) == ["d1", "d2"]
    assert Enum.map(events, & &1.status) == [:delivered, :delivered]
  end