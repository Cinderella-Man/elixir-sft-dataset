    test "fails when a message arrives within the window" do
      send(self(), :surprise)

      result =
        try do
          assert_no_message(50)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "surprise"
    end