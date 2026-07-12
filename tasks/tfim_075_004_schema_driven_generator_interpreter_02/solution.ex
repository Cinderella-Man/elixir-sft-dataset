    property ":integer produces integers" do
      check all(v <- SchemaGenerators.from_schema(:integer)) do
        assert is_integer(v)
      end
    end