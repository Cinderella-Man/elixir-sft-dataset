  test "cleanup applies the boundary rule at exactly the cutoff", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 0, 1)
    :ok = ShardedTSDB.insert(db, "m", %{}, 1000, 2)

    # now - retention_ms == 1000; chunk ending at 1000 is dropped, one ending
    # at 2000 is kept.
    Clock.set(11_000)
    assert :ok = ShardedTSDB.cleanup(db)

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {0, 20_000})
    assert points == [{1000, 2}]
  end