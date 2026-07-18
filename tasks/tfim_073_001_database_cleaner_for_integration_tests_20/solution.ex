  test "start/2 replaces an uncleaned truncation registration with a transaction one" do
    assert {:ok, :truncation} =
             DBCleaner.start(:truncation, repo: FakeRepo, tables: ["orders"])

    assert {:ok, :transaction} = DBCleaner.start(:transaction, repo: FakeRepo)

    FakeRepo.reset()
    assert DBCleaner.clean() == :ok

    calls = FakeRepo.calls()
    assert {:rollback} in calls

    refute Enum.any?(calls, fn
             {:query, _sql} -> true
             _ -> false
           end)
  end