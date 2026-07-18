  test "increase treats an equal consecutive value as a zero delta, not a reset", %{db: db} do
    # values 10, 10, 15 -> deltas 0 (10 >= 10, no reset), 5 -> total 5
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 200, 15)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :increase, 1_000)
    assert range == [{0, 5}]
  end