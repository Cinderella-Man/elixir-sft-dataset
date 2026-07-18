    property "negative depth is treated as a scalar" do
      check all(v <- JsonGenerators.value(-3)) do
        assert scalar?(v)
      end
    end