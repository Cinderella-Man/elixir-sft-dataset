    property ":boolean produces booleans" do
      check all(v <- SchemaGenerators.from_schema(:boolean)) do
        assert is_boolean(v)
      end
    end