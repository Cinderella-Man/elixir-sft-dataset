  test "a non-owner, non-allowed process cannot resolve a connection" do
    DBCleaner.start(:sandbox, repo: FakeRepo)
    parent = self()
    spawn(fn -> send(parent, {:lookup, DBCleaner.lookup()}) end)
    assert_receive {:lookup, :error}, 1000
  end