    test "evaluates to :ok when the condition is satisfied" do
      assert assert_eventually(fn -> 42 end) == :ok
    end