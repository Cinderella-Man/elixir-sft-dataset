  test "cleanup removes series with no remaining chunks", %{db: db} do
    :ok = TSDB.insert(db, "m", %{"host" => "a"}, 100, 1)

    # The series is queryable before its only chunk expires
    assert [{%{"host" => "a"}, [{100, 1}]}] =
             TSDB.query(db, "m", %{"host" => "a"}, {0, 200_000})

    # Advance well past retention
    Clock.set(100_000)
    send(db, :cleanup)

    # Series should be gone entirely
    assert [] = TSDB.query(db, "m", %{"host" => "a"}, {0, 200_000})

    # No series at all remains under this metric, for any matcher or aggregation
    assert [] = TSDB.query(db, "m", %{}, {0, 200_000})
    assert [] = TSDB.query_agg(db, "m", %{}, {0, 200_000}, :sum, 1_000)
  end