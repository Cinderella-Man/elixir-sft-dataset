  test "returns 401 when signature is wrong", %{opts: opts} do
    payload = build_event("evt_002")
    bad_sig = sign(payload, "wrong_secret")

    conn = post_webhook(opts, payload, [{"stripe-signature", bad_sig}])

    assert conn.status == 401
    assert json_body(conn)["error"] == "invalid_signature"
  end