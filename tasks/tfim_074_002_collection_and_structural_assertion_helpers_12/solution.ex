    test "failure message shows both collections" do
      message =
        try do
          assert_subset([9], [1, 2, 3])
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ "subset"
      assert message =~ "superset"
    end