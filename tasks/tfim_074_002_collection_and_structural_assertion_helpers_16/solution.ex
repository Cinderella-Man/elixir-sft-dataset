    test "fails and lists missing keys" do
      result =
        try do
          assert_has_keys(%{a: 1}, [:a, :z])
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ ":z"
    end