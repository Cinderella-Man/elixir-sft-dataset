  test "tampered body with valid in-window timestamp returns invalid_signature", %{opts: opts} do
    original = build_event("evt_005")
    hdr = header(@now, original, @secret)

    tampered =
      Jason.encode!(%{
        "id" => "evt_005",
        "type" => "charge.completed",
        "data" => %{"amount" => 999_999, "currency" => "usd"}
      })

    conn = post_webhook(opts, tampered, [{"stripe-signature", hdr}])
    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end