    property "{:one_of, schemas} produces a value from one branch" do
      schema = {:one_of, [{:integer, 0, 5}, :boolean]}

      check all(v <- SchemaGenerators.from_schema(schema)) do
        assert (is_integer(v) and v >= 0 and v <= 5) or is_boolean(v)
      end
    end