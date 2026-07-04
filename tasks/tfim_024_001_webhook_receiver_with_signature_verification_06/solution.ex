  test "returns 401 when payload has been tampered with", %{opts: opts} do
    original = build_event("evt_005")
    sig = sign(original, @secret)

    tampered =
      Jason.encode!(%{
        "id" => "evt_005",
        "type" => "charge.completed",
        "data" => %{"amount" => 999_999, "currency" => "usd"}
      })

    conn = post_webhook(opts, tampered, [{"stripe-signature", sig}])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end