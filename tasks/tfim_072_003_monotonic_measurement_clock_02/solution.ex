    test "monotonic/1 returns an integer" do
      assert is_integer(Clock.Real.monotonic(:millisecond))
    end