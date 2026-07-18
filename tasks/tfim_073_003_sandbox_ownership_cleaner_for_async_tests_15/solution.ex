  test "lookup/1 resolves the connection of an explicitly given pid" do
    parent = self()

    child =
      spawn(fn ->
        {:ok, conn} = DBCleaner.start(:sandbox, repo: FakeRepo)
        send(parent, {:ready, conn})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:ready, child_conn}, 1000

    assert {:ok, ^child_conn} = DBCleaner.lookup(child)
    assert :error = DBCleaner.lookup(self())

    send(child, :stop)
  end