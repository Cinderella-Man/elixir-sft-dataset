  test "stripe rejects wrong signature", %{opts: opts} do
    payload = build_event("evt_s2")
    conn =
      post_webhook(opts, "stripe", payload, [{"stripe-signature", stripe_sig(payload, "wrong")}])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end