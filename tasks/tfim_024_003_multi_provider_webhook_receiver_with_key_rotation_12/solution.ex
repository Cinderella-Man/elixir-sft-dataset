  test "malformed JSON returns bad_payload", %{opts: opts} do
    bad = "nope {{"
    conn = post_webhook(opts, "stripe", bad, [{"stripe-signature", stripe_sig(bad, @stripe)}])
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_payload"
  end