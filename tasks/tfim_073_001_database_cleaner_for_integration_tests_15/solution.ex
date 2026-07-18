  test "transaction: clean/0 returns :ok on success" do
    DBCleaner.start(:transaction, repo: FakeRepo)
    assert DBCleaner.clean() == :ok
  end