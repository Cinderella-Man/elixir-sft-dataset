  test "Store.store_event/4 client returns :created then :duplicate for same pair", %{
    store: store
  } do
    payload = %{"id" => "evt_direct", "type" => "x"}

    assert {:ok, :created} =
             WebhookReceiver.Store.store_event(store, "stripe", "evt_direct", payload)

    assert {:ok, :duplicate} =
             WebhookReceiver.Store.store_event(store, "stripe", "evt_direct", payload)

    assert {:ok, :created} =
             WebhookReceiver.Store.store_event(store, "github", "evt_direct", payload)

    assert {:ok, event} = WebhookReceiver.Store.get_event(store, "stripe", "evt_direct")
    assert event.payload == payload
    assert event.status == :pending

    assert length(
             Enum.filter(WebhookReceiver.Store.all_events(store), &(&1.event_id == "evt_direct"))
           ) == 2
  end