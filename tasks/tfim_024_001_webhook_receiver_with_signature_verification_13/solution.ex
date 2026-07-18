  test "MemoryStore returns duplicate for repeated event_id", %{store: store} do
    assert {:ok, :created} =
             WebhookReceiver.Store.store_event(store, "evt_200", %{"id" => "evt_200"})

    assert {:ok, :duplicate} =
             WebhookReceiver.Store.store_event(store, "evt_200", %{"id" => "evt_200"})
  end