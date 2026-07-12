  test "rate omits windows with fewer than 2 points", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 5)
    assert [] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :rate, 1_000)
  end