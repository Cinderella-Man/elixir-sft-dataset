    property "a schema generator can be nested in list_of" do
      gen = StreamData.list_of(SchemaGenerators.from_schema({:integer, 1, 3}), length: 4)

      check all(v <- gen) do
        assert length(v) == 4
        assert Enum.all?(v, fn n -> n in [1, 2, 3] end)
      end
    end