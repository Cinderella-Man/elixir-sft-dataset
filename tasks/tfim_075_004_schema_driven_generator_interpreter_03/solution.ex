    property "{:integer, min, max} stays within bounds" do
      check all(v <- SchemaGenerators.from_schema({:integer, 10, 20})) do
        assert is_integer(v)
        assert v >= 10 and v <= 20
      end
    end