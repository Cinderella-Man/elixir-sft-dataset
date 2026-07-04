  test "transaction: no truncation queries are issued on clean/0" do
    DBCleaner.start(:transaction, repo: FakeRepo, tables: ["users"])
    FakeRepo.reset()

    DBCleaner.clean()

    refute Enum.any?(FakeRepo.calls(), fn
             {:query, sql} -> String.contains?(sql, "TRUNCATE")
             _ -> false
           end)
  end