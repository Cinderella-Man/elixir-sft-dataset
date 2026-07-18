  test "named process registration works" do
    {:ok, _pid} = KeyedPool.start_link(max_concurrency: 2, name: :my_pool)

    assert {:ok, :hello} =
             KeyedPool.execute(:my_pool, :k, fn -> {:ok, :hello} end)
  end