  test "chunk duration defaults to sixty seconds when the option is omitted" do
    {:ok, db} =
      CounterTSDB.start_link(
        clock: &Clock.now/0,
        retention_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 1)

    # threshold = 20_000 - 10_000 = 10_000; the default chunk ends at
    # 0 + 60_000 = 60_000 > 10_000, so the point must survive cleanup.
    Clock.set(20_000)
    send(db, :cleanup)

    [{_labels, points}] = CounterTSDB.query(db, "reqs", %{}, {0, 10_000})
    assert points == [{0, 1}]
  end