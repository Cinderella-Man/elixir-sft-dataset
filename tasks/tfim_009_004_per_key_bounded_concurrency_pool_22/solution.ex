  test "start_link raises when max_concurrency is not an integer" do
    assert_raise ArgumentError, fn ->
      KeyedPool.start_link(max_concurrency: 1.5)
    end
  end