  test "MemoryStore returns :error for unknown event", %{store: store} do
    assert :error = WebhookReceiver.Store.get_event(store, "evt_nonexistent")
  end