    test "dispatches to Clock.Real when given the module atom" do
      assert is_integer(Clock.monotonic(Clock.Real, :second))
    end