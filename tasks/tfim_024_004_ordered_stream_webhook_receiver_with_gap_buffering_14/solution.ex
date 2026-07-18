  test "Store.deliver/2 directly buffers and drains", %{store: store} do
    e1 = %{event_id: "e1", stream_id: "z", sequence: 1, payload: %{}, status: :pending}
    e2 = %{event_id: "e2", stream_id: "z", sequence: 2, payload: %{}, status: :pending}

    assert {:ok, :buffered} = WebhookReceiver.Store.deliver(store, e2)
    assert {:ok, :received} = WebhookReceiver.Store.deliver(store, e1)
    assert WebhookReceiver.Store.last_sequence(store, "z") == 2
  end