  test "savepoint/1 before start returns :not_started" do
    assert {:error, :not_started} = DBCleaner.savepoint("a")
  end