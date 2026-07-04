  test "re-sending an already-buffered sequence returns duplicate", %{opts: opts, store: store} do
    assert deliver(opts, "e1", "s1", 1).status == 200
    assert deliver(opts, "e3", "s1", 3).status == 202

    conn = deliver(opts, "e3", "s1", 3)
    assert conn.status == 200
    assert json_body(conn)["status"] == "duplicate"
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == [3]
  end