    test ":age hits both 18 and 120 and never falls outside 18..120" do
      ages = Generators.user() |> sample(2_000) |> Enum.map(& &1.age)

      # 18 reachable, 120 reachable, and nothing below 18 or above 120.
      assert Enum.min(ages) == 18
      assert Enum.max(ages) == 120
    end