  test "cleanup removes a series with no remaining chunks", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 1)

    Clock.set(100_000)
    send(db, :cleanup)

    # The query below is handled after the :cleanup message, so it reflects
    # the cleaned-up state through the public API alone.
    assert [] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {0, 200_000})
  end