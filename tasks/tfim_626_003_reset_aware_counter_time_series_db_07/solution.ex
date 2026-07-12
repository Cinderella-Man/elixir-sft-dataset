  test "increase buckets points into separate windows", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 20)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1000, 100)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1500, 130)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 2000}, :increase, 1_000)
    assert range == [{0, 10}, {1000, 30}]
  end