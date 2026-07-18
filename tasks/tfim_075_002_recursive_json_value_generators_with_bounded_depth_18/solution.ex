    property "value(4) never exceeds depth 4" do
      check all(v <- JsonGenerators.value(4)) do
        assert depth(v) <= 4
      end
    end