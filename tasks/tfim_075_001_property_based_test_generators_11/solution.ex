    property "always produces a map with :amount and :currency" do
      check all(m <- Generators.money()) do
        assert Map.has_key?(m, :amount)
        assert Map.has_key?(m, :currency)
      end
    end