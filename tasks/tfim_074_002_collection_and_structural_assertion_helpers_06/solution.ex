    test "fails and reports the first out-of-order pair" do
      people = [%{age: 20}, %{age: 40}, %{age: 30}]

      result =
        try do
          assert_sorted_by(people, & &1.age)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "index 1"
    end