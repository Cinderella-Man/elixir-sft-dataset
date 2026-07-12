    property "{:string, min, max} respects the length bounds" do
      check all(v <- SchemaGenerators.from_schema({:string, 3, 5})) do
        assert is_binary(v)
        assert String.length(v) >= 3 and String.length(v) <= 5
      end
    end