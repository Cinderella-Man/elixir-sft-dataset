    test "fails when the message does not contain the expected text" do
      result =
        try do
          assert_raises_message(ArgumentError, "expected text", fn ->
            raise ArgumentError, "something else"
          end)

          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "did not contain"
    end