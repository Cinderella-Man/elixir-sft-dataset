    test "passes when the expected message is the next one" do
      send(self(), {:hello, 1})
      assert_next_message({:hello, 1})
    end