    test "fails and lists the missing elements" do
      result =
        try do
          assert_subset([1, 4], [1, 2, 3])
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "4"
      assert result =~ "missing"
    end