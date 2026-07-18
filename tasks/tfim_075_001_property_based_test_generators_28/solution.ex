    property "money generator can be mapped" do
      check all(m <- StreamData.map(Generators.money(), & &1.amount)) do
        assert is_integer(m)
        assert m >= 0
      end
    end