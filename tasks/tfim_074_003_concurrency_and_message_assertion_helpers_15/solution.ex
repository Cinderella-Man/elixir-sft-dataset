    test "consumes the message it matched" do
      send(self(), :only_one)
      assert AssertHelpers.next_message(:only_one, 500) == :ok
      # Mailbox must be empty now, so a follow-up wait must time out (flunk).
      assert_raise ExUnit.AssertionError, fn ->
        AssertHelpers.next_message(:only_one, 30)
      end
    end