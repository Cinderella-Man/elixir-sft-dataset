  test "start_link fails when the required max_concurrency option is missing" do
    assert_raise KeyError, fn ->
      KeyedPool.start_link([])
    end
  end