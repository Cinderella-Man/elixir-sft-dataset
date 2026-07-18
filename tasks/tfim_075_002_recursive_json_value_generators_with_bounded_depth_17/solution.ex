    property "value(2) never exceeds depth 2" do
      check all(v <- JsonGenerators.value(2)) do
        assert depth(v) <= 2
      end
    end