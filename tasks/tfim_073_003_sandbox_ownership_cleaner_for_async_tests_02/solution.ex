  test "start/2 checks out a connection and registers the owner" do
    assert {:ok, conn} = DBCleaner.start(:sandbox, repo: FakeRepo)
    assert Enum.any?(FakeRepo.calls(), &match?({:checkout, _}, &1))
    assert {:ok, ^conn} = DBCleaner.lookup()
  end