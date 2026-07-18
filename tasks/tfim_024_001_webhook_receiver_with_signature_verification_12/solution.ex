  test "MemoryStore stores and retrieves events", %{store: store} do
    assert {:ok, :created} =
             WebhookReceiver.Store.store_event(store, "evt_100", %{"id" => "evt_100"})

    assert {:ok, event} = WebhookReceiver.Store.get_event(store, "evt_100")
    assert event.event_id == "evt_100"
    assert event.status == :pending
  end