  test "Store.get_event/2 returns :error for an unknown event id", %{store: store} do
    assert WebhookReceiver.Store.get_event(store, "evt_never_stored") == :error
  end