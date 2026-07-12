    property ":string produces alphanumeric strings" do
      check all(v <- SchemaGenerators.from_schema(:string)) do
        assert is_binary(v)
        assert v == "" or String.match?(v, ~r/^[a-zA-Z0-9]+$/)
      end
    end