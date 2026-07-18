    property "works with complex domain generators" do
      gen =
        Generators.one_of_weighted([
          {1, Generators.user()},
          {1, Generators.money()}
        ])

      check all(value <- gen) do
        assert is_map(value)
        assert Map.has_key?(value, :id) or Map.has_key?(value, :amount)
      end
    end