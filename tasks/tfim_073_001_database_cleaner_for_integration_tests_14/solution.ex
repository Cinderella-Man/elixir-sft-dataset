  test "transaction: a raise from begin_transaction/0 is rescued into {:error, message}" do
    assert {:error, message} = DBCleaner.start(:transaction, repo: BeginRaisesRepo)
    assert is_binary(message)
  end