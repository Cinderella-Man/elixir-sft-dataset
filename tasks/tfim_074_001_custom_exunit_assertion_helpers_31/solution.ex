    test "a non-datetime fails the assertion even with an explicit tolerance" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_recent(apply(Function, :identity, [:not_a_datetime]), 30)
      end
    end