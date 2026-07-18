    property "{:one_of, schemas} exercises multiple branches across samples" do
      schema = {:one_of, [:integer, :boolean]}

      kinds =
        Enum.map(1..300, fn _ ->
          [v] = Enum.take(SchemaGenerators.from_schema(schema), 1)
          if is_boolean(v), do: :bool, else: :int
        end)

      assert :bool in kinds
      assert :int in kinds
    end