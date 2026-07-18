    test "flunks with expected and received on a mismatch" do
      send(self(), :unexpected)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          AssertHelpers.next_message(:wanted, 100)
        end

      assert error.message =~ "unexpected"
      assert error.message =~ "wanted"
    end