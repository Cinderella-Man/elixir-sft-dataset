    test "returns :ok when the expected message is next" do
      send(self(), {:hello, 1})
      assert AssertHelpers.next_message({:hello, 1}, 500) == :ok
    end