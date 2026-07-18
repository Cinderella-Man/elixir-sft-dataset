  test "mode: :manual never marks the owner as the global shared owner" do
    DBCleaner.start(:sandbox, repo: FakeRepo, mode: :manual)
    parent = self()

    spawn(fn -> send(parent, {:lookup, DBCleaner.lookup()}) end)
    assert_receive {:lookup, :error}, 1000
  end