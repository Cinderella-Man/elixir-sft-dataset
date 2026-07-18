    test "every role can do at least what all roles below it can do" do
      non_owner_rules =
        for {res, actions} <- @rules,
            {act, req} <- actions,
            req != :owner,
            into: %{},
            do: {{res, act}, req}

      for i <- 0..(length(@hierarchy) - 2) do
        lower = Enum.at(@hierarchy, i)
        higher = Enum.at(@hierarchy, i + 1)

        for {{res, act}, _req} <- non_owner_rules do
          if Permissions.can?(lower, res, act, @rules) do
            assert Permissions.can?(higher, res, act, @rules),
                   "#{higher} should be able to #{act} #{res} because #{lower} can"
          end
        end
      end
    end