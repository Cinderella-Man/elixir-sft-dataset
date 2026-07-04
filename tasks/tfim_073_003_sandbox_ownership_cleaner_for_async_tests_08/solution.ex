  test "clean/0 clears the shared marker so later lookups fall through" do
    DBCleaner.start(:sandbox, repo: FakeRepo, mode: :shared)
    DBCleaner.clean()

    parent = self()
    spawn(fn -> send(parent, {:lookup, DBCleaner.lookup()}) end)
    assert_receive {:lookup, :error}, 1000
  end