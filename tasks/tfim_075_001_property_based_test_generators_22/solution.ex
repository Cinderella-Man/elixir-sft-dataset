    property "all elements satisfy the inner generator's constraints" do
      check all(list <- Generators.non_empty_list(Generators.money())) do
        for m <- list do
          assert m.amount >= 0
          assert m.currency in ["USD", "EUR", "GBP", "JPY", "CHF"]
        end
      end
    end