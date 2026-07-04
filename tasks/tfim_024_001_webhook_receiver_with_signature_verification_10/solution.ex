  test "returns 400 when payload is valid JSON but missing id field", %{opts: opts} do
    payload = Jason.encode!(%{"type" => "charge.completed", "data" => %{}})
    sig = sign(payload, @secret)

    conn = post_webhook(opts, payload, [{"stripe-signature", sig}])

    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end