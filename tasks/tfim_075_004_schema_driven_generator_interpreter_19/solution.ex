    property "{:string, min_len, max_len} supports zero-length bounds" do
      check all(v <- SchemaGenerators.from_schema({:string, 0, 0})) do
        assert v == ""
      end
    end