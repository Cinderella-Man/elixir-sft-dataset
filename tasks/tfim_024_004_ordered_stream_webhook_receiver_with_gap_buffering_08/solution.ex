  test "streams are independent", %{opts: opts, store: store} do
    assert deliver(opts, "a1", "sa", 1).status == 200
    assert deliver(opts, "b3", "sb", 3).status == 202

    assert WebhookReceiver.Store.last_sequence(store, "sa") == 1
    assert WebhookReceiver.Store.last_sequence(store, "sb") == 0
    assert WebhookReceiver.Store.buffered_sequences(store, "sb") == [3]
  end