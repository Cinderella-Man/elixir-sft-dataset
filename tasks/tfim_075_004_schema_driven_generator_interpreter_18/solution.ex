    property "{:integer, min, max} supports min == max" do
      check all(v <- SchemaGenerators.from_schema({:integer, 7, 7})) do
        assert v == 7
      end
    end