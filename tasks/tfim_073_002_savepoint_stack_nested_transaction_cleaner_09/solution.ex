  test "clean/0 rolls back the outer transaction and clears state" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    FakeRepo.reset()

    assert :ok = DBCleaner.clean()
    assert {:rollback} in FakeRepo.calls()
    assert DBCleaner.active_savepoints() == []
  end