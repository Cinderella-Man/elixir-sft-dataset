    test "fails when a different message arrives" do
      send(self(), :unexpected)

      result =
        try do
          assert_next_message(:wanted)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "unexpected"
      assert result =~ "wanted"
    end