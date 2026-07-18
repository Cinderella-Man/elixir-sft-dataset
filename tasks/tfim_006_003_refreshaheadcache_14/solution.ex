  test "invalid refresh_threshold raises" do
    assert_raise ArgumentError, fn ->
      RefreshAheadCache.start_link(refresh_threshold: 0.0)
    end

    assert_raise ArgumentError, fn ->
      RefreshAheadCache.start_link(refresh_threshold: 1.5)
    end
  end