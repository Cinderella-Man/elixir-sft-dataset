  test "missing id returns bad_payload", %{opts: opts} do
    payload = Jason.encode!(%{"type" => "x"})

    conn =
      post_webhook(opts, "stripe", payload, [{"stripe-signature", stripe_sig(payload, @stripe)}])

    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end