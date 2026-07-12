    property "{:map, schema_map} produces fixed-shape maps" do
      schema =
        {:map,
         %{
           id: {:integer, 1, 100},
           active: :boolean,
           name: {:string, 1, 6}
         }}

      check all(v <- SchemaGenerators.from_schema(schema)) do
        assert is_map(v)
        assert Map.keys(v) |> Enum.sort() == [:active, :id, :name]
        assert v.id >= 1 and v.id <= 100
        assert is_boolean(v.active)
        assert String.length(v.name) >= 1 and String.length(v.name) <= 6
      end
    end