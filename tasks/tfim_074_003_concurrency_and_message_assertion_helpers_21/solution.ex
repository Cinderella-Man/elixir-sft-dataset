    test "flunks showing the message that unexpectedly arrived" do
      send(self(), :surprise)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          AssertHelpers.no_message(50)
        end

      assert error.message =~ "surprise"
    end