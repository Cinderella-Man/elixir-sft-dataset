  test "state does not bleed across sequential start/clean cycles" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    DBCleaner.clean()

    DBCleaner.start(:savepoint, repo: FakeRepo)
    assert DBCleaner.active_savepoints() == []
  end