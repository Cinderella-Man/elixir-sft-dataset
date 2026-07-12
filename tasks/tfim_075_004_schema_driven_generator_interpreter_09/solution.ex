    property "{:list, schema, opts} respects length bounds" do
      schema = {:list, {:integer, 0, 9}, [min: 2, max: 4]}

      check all(v <- SchemaGenerators.from_schema(schema)) do
        assert is_list(v)
        assert length(v) >= 2 and length(v) <= 4
        assert Enum.all?(v, fn n -> n >= 0 and n <= 9 end)
      end
    end