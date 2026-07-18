  test "transaction: clean/0 issues no query!/3 call at all even when tables were given" do
    DBCleaner.start(:transaction, repo: FakeRepo, tables: ["users", "posts"])
    FakeRepo.reset()

    assert DBCleaner.clean() == :ok

    assert FakeRepo.calls() == [{:rollback}]
  end