    test "failure message shows the present keys" do
      message =
        try do
          assert_has_keys(%{a: 1, b: 2}, [:missing])
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ "present"
    end