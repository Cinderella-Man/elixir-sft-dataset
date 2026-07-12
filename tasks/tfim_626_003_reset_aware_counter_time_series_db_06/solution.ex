  test "increase omits windows with fewer than 2 points", %{db: db} do
    # window [0,1000): only 1 point -> omitted
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 42)
    # window [1000,2000): 2 points -> increase 50
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1100, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1600, 60)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 2000}, :increase, 1_000)
    assert range == [{1000, 50}]
  end