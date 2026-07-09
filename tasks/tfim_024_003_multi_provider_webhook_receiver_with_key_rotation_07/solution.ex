  test "unknown provider returns 404 unknown_provider", %{opts: opts} do
    payload = build_event("evt_x")

    conn =
      post_webhook(opts, "paypal", payload, [{"stripe-signature", stripe_sig(payload, @stripe)}])

    assert conn.status == 404
    assert json_body(conn)["error"] == "unknown_provider"
  end