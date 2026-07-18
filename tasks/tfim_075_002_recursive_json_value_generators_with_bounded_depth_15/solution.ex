    property "value(0) is always a scalar" do
      check all(v <- JsonGenerators.value(0)) do
        assert scalar?(v)
        assert depth(v) == 0
      end
    end