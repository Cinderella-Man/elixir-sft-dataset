  test "POST to unknown path returns 404", %{opts: opts} do
    payload = build_event("evt_999")

    conn =
      do_request(opts, :post, "/api/webhooks/unknown", payload, [
        {"stripe-signature", header(@now, payload, @secret)}
      ])

    assert conn.status == 404
  end