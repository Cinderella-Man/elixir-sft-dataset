  test "github accepts a rotated-out (old) secret", %{opts: opts} do
    payload = build_event("evt_g2")

    conn =
      post_webhook(opts, "github", payload, [{"x-hub-signature-256", gh_sig(payload, @gh_old)}])

    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
  end