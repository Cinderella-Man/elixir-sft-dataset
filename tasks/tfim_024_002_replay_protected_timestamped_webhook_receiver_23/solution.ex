  test "Store.store_event/3 reports created then duplicate and keeps first payload",
       %{store: store} do
    assert {:ok, :created} = WebhookReceiver.Store.store_event(store, "evt_sv", %{"n" => 1})
    assert {:ok, :duplicate} = WebhookReceiver.Store.store_event(store, "evt_sv", %{"n" => 2})
    assert {:ok, event} = WebhookReceiver.Store.get_event(store, "evt_sv")
    assert event.payload == %{"n" => 1}
    assert event.status == :pending
    assert length(WebhookReceiver.Store.all_events(store)) == 1
  end