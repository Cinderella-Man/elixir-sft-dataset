  test "an owner resolves to its own connection even when a shared owner exists" do
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

    assert {:ok, own_conn} = DBCleaner.start(:sandbox, repo: FakeRepo)
    refute own_conn == shared_conn
    assert {:ok, ^own_conn} = DBCleaner.lookup()

    send(shared_owner, :stop)
  end