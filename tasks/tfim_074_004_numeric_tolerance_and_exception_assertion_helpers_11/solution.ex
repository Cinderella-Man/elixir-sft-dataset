    test "fails when actual is outside the tolerance" do
      result =
        try do
          assert_within_pct(120, 100, 5)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "allowed"
      assert result =~ "120"
    end