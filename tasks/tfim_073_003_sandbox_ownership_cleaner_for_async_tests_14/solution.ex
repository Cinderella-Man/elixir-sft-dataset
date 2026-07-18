  test "an explicit allowance takes precedence over the global shared owner" do
    parent = self()

    shared_owner =
      spawn(fn ->
        {:ok, shared_conn} = DBCleaner.start(:sandbox, repo: FakeRepo, mode: :shared)
        send(parent, {:shared_ready, shared_conn})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:shared_ready, shared_conn}, 1000

    {:ok, conn} = DBCleaner.start(:sandbox, repo: FakeRepo, mode: :manual)
    refute conn == shared_conn

    child =
      spawn(fn ->
        receive do
          :go -> send(parent, {:lookup, DBCleaner.lookup()})
        end
      end)

    assert {:ok, ^child} = DBCleaner.allow(self(), child)
    send(child, :go)
    assert_receive {:lookup, {:ok, ^conn}}, 1000

    send(shared_owner, :stop)
  end