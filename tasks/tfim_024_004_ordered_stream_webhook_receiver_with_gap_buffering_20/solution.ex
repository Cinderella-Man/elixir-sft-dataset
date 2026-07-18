  test "empty stripe-signature header returns 401", %{opts: opts, store: store} do
    payload = build_event("e1", "s1", 1)

    conn =
      do_request(opts, :post, "/api/webhooks/stripe", payload, [{"stripe-signature", ""}])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
    assert WebhookReceiver.Store.last_sequence(store, "s1") == 0
    assert WebhookReceiver.Store.delivered_events(store, "s1") == []
  end