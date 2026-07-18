  test "retention defaults to one hour when the option is omitted" do
    {:ok, db} =
      CounterTSDB.start_link(
        clock: &Clock.now/0,
        chunk_duration_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 1)

    # threshold = 100_000 - 3_600_000 < 0, so the chunk survives.
    Clock.set(100_000)
    send(db, :cleanup)
    [{_labels, points}] = CounterTSDB.query(db, "reqs", %{}, {0, 10_000})
    assert points == [{0, 1}]

    # threshold = 3_601_000 - 3_600_000 = 1_000; chunk ends at 1_000 -> expired.
    Clock.set(3_601_000)
    send(db, :cleanup)
    assert [] = CounterTSDB.query(db, "reqs", %{}, {0, 10_000})
  end