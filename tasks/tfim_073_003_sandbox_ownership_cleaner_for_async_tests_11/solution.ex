  test "clean/0 revokes allowances pointing at the cleaned owner" do
    DBCleaner.start(:sandbox, repo: FakeRepo, mode: :manual)
    parent = self()

    child =
      spawn(fn ->
        receive do
          :go -> send(parent, {:lookup, DBCleaner.lookup()})
        end
      end)

    assert {:ok, ^child} = DBCleaner.allow(self(), child)
    assert :ok = DBCleaner.clean()

    send(child, :go)
    assert_receive {:lookup, :error}, 1000
  end