    test "flunks on timeout when the mailbox stays empty" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          AssertHelpers.next_message(:never, 40)
        end

      assert error.message =~ "timed out"
      assert error.message =~ "40"
    end