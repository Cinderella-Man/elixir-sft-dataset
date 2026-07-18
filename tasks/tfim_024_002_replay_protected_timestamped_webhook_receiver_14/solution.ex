  test "missing id returns bad_payload", %{opts: opts} do
    payload = Jason.encode!(%{"type" => "charge.completed"})
    conn = post_webhook(opts, payload, [{"stripe-signature", header(@now, payload, @secret)}])
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end