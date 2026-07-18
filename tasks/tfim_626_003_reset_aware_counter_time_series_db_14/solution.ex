  test "label order does not create duplicate series", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"a" => "1", "b" => "2"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"b" => "2", "a" => "1"}, 500, 20)

    [{_labels, [{0, inc}]}] =
      CounterTSDB.query_range(db, "reqs", %{"a" => "1", "b" => "2"}, {0, 1000}, :increase, 1_000)

    assert inc == 20
  end