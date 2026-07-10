  test "transaction: start/2 returns {:ok, :transaction} on success" do
    assert DBCleaner.start(:transaction, repo: FakeRepo) == {:ok, :transaction}
  end