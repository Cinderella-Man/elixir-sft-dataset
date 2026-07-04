  test "shared mode resolves any process to the shared owner's connection" do
    {:ok, conn} = DBCleaner.start(:sandbox, repo: FakeRepo, mode: :shared)
    parent = self()
    spawn(fn -> send(parent, {:lookup, DBCleaner.lookup()}) end)
    assert_receive {:lookup, {:ok, ^conn}}, 1000
  end