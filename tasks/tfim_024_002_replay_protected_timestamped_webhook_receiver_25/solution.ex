  test "all_events returns every distinct stored event as a list", %{opts: opts, store: store} do
    for id <- ["evt_a1", "evt_a2", "evt_a3"] do
      payload = build_event(id)
      conn = post_webhook(opts, payload, [{"stripe-signature", header(@now, payload, @secret)}])
      assert conn.status == 200
    end

    events = WebhookReceiver.Store.all_events(store)
    assert is_list(events)
    assert Enum.sort(Enum.map(events, & &1.event_id)) == ["evt_a1", "evt_a2", "evt_a3"]
  end