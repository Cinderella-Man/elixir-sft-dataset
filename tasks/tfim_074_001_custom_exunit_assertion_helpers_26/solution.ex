    test "reported elapsed is non-negative and may be 0ms" do
      elapsed_values =
        Enum.map(1..20, fn _ ->
          message =
            try do
              assert_eventually(fn -> false end, 0, 0)
              ""
            rescue
              e in ExUnit.AssertionError -> e.message
            end

          case Regex.run(~r/elapsed\D*(\d+)ms/, message) do
            [_, digits] -> String.to_integer(digits)
            _ -> -1
          end
        end)

      assert Enum.all?(elapsed_values, &(&1 >= 0))
      assert Enum.any?(elapsed_values, &(&1 == 0))
    end