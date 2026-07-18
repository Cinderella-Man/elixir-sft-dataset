    test "passes when the right exception with matching message is raised" do
      assert_raises_message(ArgumentError, "bad input", fn ->
        raise ArgumentError, "bad input value"
      end)
    end