  test "transaction: start/2 begins a transaction" do
    DBCleaner.start(:transaction, repo: FakeRepo, tables: [])
    assert {:begin} in FakeRepo.calls()
  end