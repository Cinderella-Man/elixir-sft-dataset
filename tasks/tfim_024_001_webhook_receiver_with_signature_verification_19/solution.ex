  test "POST to an unknown path returns 404", %{opts: opts} do
    payload = build_event("evt_999")
    sig = sign(payload, @secret)

    conn = do_request(opts, :post, "/api/webhooks/unknown", payload, [{"stripe-signature", sig}])
    assert conn.status == 404
  end