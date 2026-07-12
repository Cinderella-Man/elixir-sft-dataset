  test "increase over a monotonic window is the difference", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 100)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 500, 160)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :increase, 1_000)
    assert range == [{0, 60}]
  end