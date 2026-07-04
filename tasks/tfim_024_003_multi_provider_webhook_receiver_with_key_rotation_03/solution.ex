  test "github provider verifies with prefix and current secret", %{opts: opts} do
    payload = build_event("evt_g1")
    conn =
      post_webhook(opts, "github", payload, [{"x-hub-signature-256", gh_sig(payload, @gh_new)}])

    assert conn.status == 200
    assert json_body(conn)["status"] == "received"
  end