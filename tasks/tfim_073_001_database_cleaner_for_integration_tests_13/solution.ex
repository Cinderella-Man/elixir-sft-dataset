  test "start/2 with an unknown strategy returns {:error, message} with a String message" do
    assert {:error, message} = DBCleaner.start(:bogus, repo: FakeRepo)
    assert is_binary(message)
  end