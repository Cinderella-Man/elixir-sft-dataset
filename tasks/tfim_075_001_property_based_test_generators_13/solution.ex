    property ":currency is always one of the allowed currency codes" do
      check all(m <- Generators.money()) do
        assert m.currency in ["USD", "EUR", "GBP", "JPY", "CHF"]
      end
    end