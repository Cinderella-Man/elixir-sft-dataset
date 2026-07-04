  test "ensure_registry/2 is idempotent" do
    assert {:ok, pid} = DBCleaner.ensure_registry()
    assert {:ok, ^pid} = DBCleaner.ensure_registry()
  end