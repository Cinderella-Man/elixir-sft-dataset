  test "transaction: a raise from rollback/0 makes clean/0 return {:error, message}" do
    DBCleaner.start(:transaction, repo: CleanRaisesRepo)
    assert {:error, message} = DBCleaner.clean()
    assert is_binary(message)
  end