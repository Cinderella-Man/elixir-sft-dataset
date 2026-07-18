  test "sequence strictly below last_seq is duplicate and does not re-deliver", %{
    opts: opts,
    store: store
  } do
    for seq <- 1..3, do: assert(deliver(opts, "e#{seq}", "s1", seq).status == 200)

    conn = deliver(opts, "e1-again", "s1", 1)
    assert conn.status == 200
    assert json_body(conn)["status"] == "duplicate"

    assert WebhookReceiver.Store.last_sequence(store, "s1") == 3
    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == []

    events = WebhookReceiver.Store.delivered_events(store, "s1")
    assert Enum.map(events, & &1.event_id) == ["e1", "e2", "e3"]
  end