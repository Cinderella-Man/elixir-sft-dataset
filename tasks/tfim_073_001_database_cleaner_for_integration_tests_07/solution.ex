  test "transaction: clean/0 rolls back the transaction" do
    DBCleaner.start(:transaction, repo: FakeRepo, tables: [])
    FakeRepo.reset()

    DBCleaner.clean()

    assert {:rollback} in FakeRepo.calls()
  end