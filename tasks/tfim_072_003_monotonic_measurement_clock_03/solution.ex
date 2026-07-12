    test "monotonic time is non-decreasing" do
      a = Clock.Real.monotonic(:microsecond)
      b = Clock.Real.monotonic(:microsecond)
      assert b >= a
    end