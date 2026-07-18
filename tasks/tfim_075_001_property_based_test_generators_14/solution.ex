    property "produces all currencies across many samples" do
      currencies =
        Enum.map(1..300, fn _ ->
          [m] = Enum.take(Generators.money(), 1)
          m.currency
        end)

      for c <- ["USD", "EUR", "GBP", "JPY", "CHF"] do
        assert c in currencies, "Expected currency #{c} to appear in 300 samples"
      end
    end