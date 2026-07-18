    property "value can be filtered to only containers" do
      gen = StreamData.filter(JsonGenerators.value(3), fn v -> is_list(v) or is_map(v) end)

      check all(v <- gen) do
        assert is_list(v) or is_map(v)
        assert depth(v) <= 3
      end
    end