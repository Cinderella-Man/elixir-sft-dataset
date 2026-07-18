  test "terminate/2 erases the persistent_term fast-path registry on shutdown" do
    Process.flag(:trap_exit, true)
    {:ok, cl} = CacheLayer.start_link([])
    Tracker.set({:ok, :v})

    assert {:ok, :v} = CacheLayer.fetch(cl, :users, "u:1", &Tracker.fallback/0)
    assert {:ok, :v} = CacheLayer.fetch(cl, :posts, "p:1", &Tracker.fallback/0)

    users_key = {CacheLayer, cl, :users}
    posts_key = {CacheLayer, cl, :posts}

    # The registry entries exist while the process is alive.
    users_tid = :persistent_term.get(users_key)
    posts_tid = :persistent_term.get(posts_key)
    refute :ets.info(users_tid) == :undefined
    refute :ets.info(posts_tid) == :undefined

    # Graceful stop must run terminate/2, which erases every registry entry.
    :ok = GenServer.stop(cl)

    assert :persistent_term.get(users_key, :cleared) == :cleared
    assert :persistent_term.get(posts_key, :cleared) == :cleared
  end