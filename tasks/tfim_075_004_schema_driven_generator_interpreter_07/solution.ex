    property "{:enum, values} only produces listed values" do
      values = [:red, :green, :blue]

      check all(v <- SchemaGenerators.from_schema({:enum, values})) do
        assert v in values
      end
    end