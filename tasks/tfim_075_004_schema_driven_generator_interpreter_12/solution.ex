    property "{:optional, schema} produces nil or a conforming value" do
      check all(v <- SchemaGenerators.from_schema({:optional, {:integer, 1, 5}})) do
        assert is_nil(v) or (is_integer(v) and v >= 1 and v <= 5)
      end
    end