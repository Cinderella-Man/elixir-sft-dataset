    property "{:optional, schema} produces both nil and values across samples" do
      results =
        Enum.map(1..300, fn _ ->
          [v] = Enum.take(SchemaGenerators.from_schema({:optional, :integer}), 1)
          is_nil(v)
        end)

      assert true in results
      assert false in results
    end