    property "{:list, schema} produces lists of conforming values" do
      check all(v <- SchemaGenerators.from_schema({:list, :boolean})) do
        assert is_list(v)
        assert Enum.all?(v, &is_boolean/1)
      end
    end