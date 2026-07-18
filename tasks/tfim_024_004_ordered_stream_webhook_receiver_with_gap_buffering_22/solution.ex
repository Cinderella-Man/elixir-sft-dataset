  test "buffered_sequences returns sorted seqs regardless of arrival order", %{
    opts: opts,
    store: store
  } do
    assert deliver(opts, "e1", "s1", 1).status == 200
    assert deliver(opts, "e7", "s1", 7).status == 202
    assert deliver(opts, "e3", "s1", 3).status == 202
    assert deliver(opts, "e5", "s1", 5).status == 202

    assert WebhookReceiver.Store.buffered_sequences(store, "s1") == [3, 5, 7]
    assert WebhookReceiver.Store.last_sequence(store, "s1") == 1
  end