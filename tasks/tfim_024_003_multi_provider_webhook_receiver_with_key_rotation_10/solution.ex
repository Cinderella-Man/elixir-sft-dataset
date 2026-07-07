  test "same id under different providers stored independently", %{opts: opts, store: store} do
    payload = build_event("shared_id")

    c1 =
      post_webhook(opts, "stripe", payload, [{"stripe-signature", stripe_sig(payload, @stripe)}])
    c2 =
      post_webhook(opts, "github", payload, [{"x-hub-signature-256", gh_sig(payload, @gh_new)}])

    assert json_body(c1)["status"] == "received"
    assert json_body(c2)["status"] == "received"

    assert {:ok, _} = WebhookReceiver.Store.get_event(store, "stripe", "shared_id")
    assert {:ok, _} = WebhookReceiver.Store.get_event(store, "github", "shared_id")
    assert length(WebhookReceiver.Store.all_events(store)) == 2
  end