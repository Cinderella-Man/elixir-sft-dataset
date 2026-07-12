  test "rate accounts for a reset within the window", %{db: db} do
    # values 10,15,5,8 at 0,100,200,300 -> increase 13; elapsed (300-0)/1000=0.3
    # rate = 13 / 0.3 = 43.333...
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 15)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 200, 5)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 300, 8)

    [{_labels, [{0, rate}]}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :rate, 1_000)
    assert_in_delta rate, 43.3333, 0.01
  end