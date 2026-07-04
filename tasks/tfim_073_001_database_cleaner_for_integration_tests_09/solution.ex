  test "switching strategy between tests does not bleed state" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["orders"])
    DBCleaner.clean()
    truncation_calls = FakeRepo.calls()

    FakeRepo.reset()

    DBCleaner.start(:transaction, repo: FakeRepo, tables: [])
    DBCleaner.clean()
    transaction_calls = FakeRepo.calls()

    # Truncation run produced TRUNCATE queries, transaction run did not
    assert Enum.any?(truncation_calls, fn
             {:query, sql} -> String.contains?(sql, "TRUNCATE")
             _ -> false
           end)

    refute Enum.any?(transaction_calls, fn
             {:query, sql} -> String.contains?(sql, "TRUNCATE")
             _ -> false
           end)
  end