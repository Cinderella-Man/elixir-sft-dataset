  test "distinct event IDs are stored independently", %{opts: opts, store: store} do
    for i <- 1..5 do
      id = "evt_multi_#{i}"
      payload = build_event(id)
      sig = sign(payload, @secret)

      conn = post_webhook(opts, payload, [{"stripe-signature", sig}])
      assert conn.status == 200
      assert json_body(conn)["status"] == "received"
    end

    events = WebhookReceiver.Store.all_events(store)
    assert length(events) == 5
  end