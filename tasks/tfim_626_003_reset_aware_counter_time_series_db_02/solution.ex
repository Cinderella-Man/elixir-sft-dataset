  test "insert and query returns sorted points within inclusive range", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 300, 30)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 200, 20)

    [{%{"i" => "a"}, points}] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {0, 500})
    assert points == [{100, 10}, {200, 20}, {300, 30}]
  end