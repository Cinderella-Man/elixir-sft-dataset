  test "start/2 begins an outer transaction and empty stack" do
    assert {:ok, :savepoint} = DBCleaner.start(:savepoint, repo: FakeRepo)
    assert {:begin} in FakeRepo.calls()
    assert DBCleaner.active_savepoints() == []
  end