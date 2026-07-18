    property "every produced value is JSON-shaped (scalar, list, or map)" do
      check all(v <- JsonGenerators.value(3)) do
        assert scalar?(v) or is_list(v) or is_map(v)
      end
    end