  test "provider config without :prefix key defaults to empty prefix", %{store: store} do
    providers = %{"acme" => %{secrets: [@stripe], header: "acme-signature"}}
    opts = [providers: providers, store: store]
    payload = build_event("evt_no_prefix")

    conn = post_webhook(opts, "acme", payload, [{"acme-signature", hmac_hex(payload, @stripe)}])

    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
    assert {:ok, event} = WebhookReceiver.Store.get_event(store, "acme", "evt_no_prefix")
    assert event.event_id == "evt_no_prefix"
  end