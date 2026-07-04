  test "clean/0 checks the connection in and removes ownership" do
    {:ok, conn} = DBCleaner.start(:sandbox, repo: FakeRepo)
    assert {:ok, ^conn} = DBCleaner.lookup()

    assert :ok = DBCleaner.clean()
    assert Enum.any?(FakeRepo.calls(), &match?({:checkin, ^conn}, &1))
    assert :error = DBCleaner.lookup()
  end