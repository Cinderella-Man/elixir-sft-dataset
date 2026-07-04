  test "already-delivered sequence returns duplicate", %{opts: opts, store: store} do
    assert deliver(opts, "e1", "s1", 1).status == 200
    conn = deliver(opts, "e1", "s1", 1)
    assert conn.status == 200
    assert json_body(conn)["status"] == "duplicate"
    assert WebhookReceiver.Store.last_sequence(store, "s1") == 1
  end