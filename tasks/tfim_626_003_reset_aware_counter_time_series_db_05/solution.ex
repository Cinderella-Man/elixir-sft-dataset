  test "increase treats a mid-window drop as a counter reset", %{db: db} do
    # values 10, 15, 5, 8 -> deltas 5, (reset)5, 3 -> total 13
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 15)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 200, 5)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 300, 8)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :increase, 1_000)
    assert range == [{0, 13}]
  end