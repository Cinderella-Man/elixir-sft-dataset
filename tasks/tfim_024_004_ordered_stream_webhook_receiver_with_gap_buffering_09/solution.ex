  test "invalid signature returns 401", %{opts: opts} do
    payload = build_event("e1", "s1", 1)

    conn =
      do_request(opts, :post, "/api/webhooks/stripe", payload, [
        {"stripe-signature", sign(payload, "wrong")}
      ])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end