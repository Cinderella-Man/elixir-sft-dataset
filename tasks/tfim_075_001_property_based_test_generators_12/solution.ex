    property ":amount is always a non-negative integer within bounds" do
      check all(m <- Generators.money()) do
        assert is_integer(m.amount)
        assert m.amount >= 0
        assert m.amount <= 10_000_000
      end
    end