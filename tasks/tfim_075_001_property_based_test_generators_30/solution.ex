    property "non_empty_list works with one_of_weighted" do
      gen =
        Generators.non_empty_list(
          Generators.one_of_weighted([
            {3, Generators.money()},
            {1, StreamData.constant(%{amount: 0, currency: "USD"})}
          ])
        )

      check all(list <- gen) do
        assert length(list) >= 1

        for item <- list do
          assert item.amount >= 0
          assert item.currency in ["USD", "EUR", "GBP", "JPY", "CHF"]
        end
      end
    end