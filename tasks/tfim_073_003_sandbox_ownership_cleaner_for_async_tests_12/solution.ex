  test "an allowance does not survive clean/0 into the owner's next checkout" do
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

    # The same process checks out a fresh connection; the old allowance was
    # dropped, so the previously-allowed process must not reach the new one.
    assert {:ok, conn2} = DBCleaner.start(:sandbox, repo: FakeRepo, mode: :manual)
    assert {:ok, ^conn2} = DBCleaner.lookup()

    send(child, :go)
    assert_receive {:lookup, :error}, 1000
  end