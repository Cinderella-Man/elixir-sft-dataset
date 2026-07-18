    property "a schema generator can be mapped" do
      gen = StreamData.map(SchemaGenerators.from_schema({:integer, 1, 10}), &(&1 * 2))

      check all(v <- gen) do
        assert rem(v, 2) == 0
        assert v >= 2 and v <= 20
      end
    end