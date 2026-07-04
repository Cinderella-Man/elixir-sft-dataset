  test "terminating the cache erases the persistent_term registry for its tables" do
    # Start an unsupervised instance we fully control the lifecycle of, so we can
    # observe what terminate/2 does on a clean shutdown. terminate/2 must erase
    # the persistent_term entries it created for each table (ETS tables are freed
    # automatically when the owner dies, but persistent_term is NOT — only
    # terminate/2 can clean those up).
    {:ok, pid} = CacheLayer.start_link([])

    assert {:ok, :db_value} = CacheLayer.fetch(pid, :users, "u:1", fn -> :db_value end)
    assert {:ok, :db_value} = CacheLayer.fetch(pid, :posts, "p:1", fn -> :db_value end)

    users_key = {CacheLayer, pid, :users}
    posts_key = {CacheLayer, pid, :posts}

    # While alive, the registry entries exist and point at real ETS tables.
    users_tid = :persistent_term.get(users_key, :no_table)
    posts_tid = :persistent_term.get(posts_key, :no_table)
    assert users_tid != :no_table
    assert posts_tid != :no_table
    assert :ets.info(users_tid) != :undefined
    assert :ets.info(posts_tid) != :undefined

    # Cleanly stop the process; terminate/2 must run and scrub the registry.
    ref = Process.monitor(pid)
    :ok = GenServer.stop(pid, :normal, 1_000)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000

    # If terminate/2 is gutted, these persistent_term entries linger as stale
    # references and these assertions fail.
    assert :persistent_term.get(users_key, :no_table) == :no_table
    assert :persistent_term.get(posts_key, :no_table) == :no_table

    # The ETS tables terminate/2 deleted must also be gone.
    assert :ets.info(users_tid) == :undefined
    assert :ets.info(posts_tid) == :undefined
  end