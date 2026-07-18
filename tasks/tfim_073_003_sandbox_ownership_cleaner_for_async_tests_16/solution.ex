  test "a second clean/0 after a successful clean does not check the connection in twice" do
    {:ok, conn} = DBCleaner.start(:sandbox, repo: FakeRepo)

    assert :ok = DBCleaner.clean()
    assert :ok = DBCleaner.clean()

    checkins = Enum.filter(FakeRepo.calls(), &match?({:checkin, ^conn}, &1))
    assert length(checkins) == 1
  end