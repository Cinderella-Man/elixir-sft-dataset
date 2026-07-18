  test "default timeout_ms is 30 minutes when the option is omitted" do
    {:ok, store} =
      SessionStore.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    {:ok, id_a} = SessionStore.create(store, %{user: "a"})
    {:ok, id_b} = SessionStore.create(store, %{user: "b"})

    # Just under 30 minutes: still alive (upper bound on the default).
    Clock.advance(1_799_999)
    assert {:ok, %{user: "a"}} = SessionStore.get(store, id_a)

    # Just past 30 minutes from creation: expired (lower bound on the default).
    Clock.advance(2)
    assert {:error, :not_found} = SessionStore.get(store, id_b)
  end