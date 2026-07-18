  test "a :name registered server serves fetch, put and invalidate through the name" do
    start_supervised!(Supervisor.child_spec({CacheLayer, [name: :cl_named]}, id: :cl_named))

    assert {:ok, :v1} = CacheLayer.fetch(:cl_named, :users, "u:1", fn -> Store.loaded(:v1) end)

    boom = fn -> raise "a cache hit must not call the loader" end
    assert {:ok, :v1} = CacheLayer.fetch(:cl_named, :users, "u:1", boom)

    assert {:ok, :v2} = CacheLayer.put(:cl_named, :users, "u:1", :v2, &Store.write/0)
    assert {:ok, :v2} = CacheLayer.fetch(:cl_named, :users, "u:1", boom)

    assert :ok = CacheLayer.invalidate(:cl_named, :users, "u:1")
    assert {:ok, :v3} = CacheLayer.fetch(:cl_named, :users, "u:1", fn -> Store.loaded(:v3) end)
    assert Store.counts().loads == 2
  end