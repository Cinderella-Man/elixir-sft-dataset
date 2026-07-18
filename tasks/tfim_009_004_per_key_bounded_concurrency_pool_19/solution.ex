  test "start_link raises on invalid max_concurrency" do
    assert_raise ArgumentError, fn ->
      KeyedPool.start_link(max_concurrency: 0)
    end

    assert_raise ArgumentError, fn ->
      KeyedPool.start_link(max_concurrency: -1)
    end
  end