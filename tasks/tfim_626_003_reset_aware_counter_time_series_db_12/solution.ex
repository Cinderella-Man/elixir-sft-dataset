  test "rate omits a zero-elapsed window but keeps the other windows", %{db: db} do
    # window [0,1000): two points sharing timestamp 100 -> last == first -> omitted
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 5)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 9)
    # window [1000,2000): increase 50 over (1600-1100)/1000 = 0.5s -> 100.0
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1100, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1600, 60)

    [{_labels, [{1000, rate}]}] =
      CounterTSDB.query_range(db, "reqs", %{}, {0, 2000}, :rate, 1_000)

    assert_in_delta rate, 100.0, 0.01
  end