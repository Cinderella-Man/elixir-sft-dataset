    test "works with the real clock and yields a non-negative elapsed" do
      {result, elapsed} = Clock.measure(Clock.Real, fn -> :ok end)
      assert result == :ok
      assert is_integer(elapsed)
      assert elapsed >= 0
    end