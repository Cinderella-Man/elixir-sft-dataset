  test "stopping the server erases its :persistent_term entries and frees its ETS tables" do
    {:ok, pid} = CacheLayer.start_link([])

    # Touch two tables so the server publishes a tid for each via :persistent_term.
    {:ok, :db_value} = CacheLayer.fetch(pid, :users, "u:1", &CallTracker.fallback/0)
    {:ok, :db_value} = CacheLayer.fetch(pid, :posts, "p:1", &CallTracker.fallback/0)

    users_tid = :persistent_term.get({CacheLayer, pid, :users})
    posts_tid = :persistent_term.get({CacheLayer, pid, :posts})
    assert :ets.info(users_tid) != :undefined

    :ok = GenServer.stop(pid)

    # :persistent_term is never garbage-collected, so a server that skips its
    # terminate/2 cleanup leaks an entry on every shutdown — both published tids
    # must be gone.
    assert :persistent_term.get({CacheLayer, pid, :users}, :erased) == :erased
    assert :persistent_term.get({CacheLayer, pid, :posts}, :erased) == :erased

    # The ETS tables owned by the now-dead process are freed as well.
    assert :ets.info(users_tid) == :undefined
    assert :ets.info(posts_tid) == :undefined
  end