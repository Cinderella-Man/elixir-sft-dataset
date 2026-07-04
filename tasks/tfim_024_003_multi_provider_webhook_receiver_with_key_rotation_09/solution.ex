  test "github signature sent to stripe (wrong header) is rejected", %{opts: opts} do
    payload = build_event("evt_s4")
    conn =
      post_webhook(opts, "stripe", payload, [{"x-hub-signature-256", gh_sig(payload, @stripe)}])

    assert conn.status == 401
  end