  test "map schema with optional list-valued field nests generators correctly" do
    schema =
      {:map,
       %{
         tags: {:optional, {:list, {:string, 1, 3}, [min: 1, max: 2]}},
         n: {:integer, 0, 3}
       }}

    values = SchemaGenerators.from_schema(schema) |> Enum.take(300)

    for v <- values do
      assert Map.keys(v) |> Enum.sort() == [:n, :tags]
      assert v.n >= 0 and v.n <= 3

      case v.tags do
        nil ->
          :ok

        list ->
          assert is_list(list)
          assert length(list) >= 1 and length(list) <= 2

          assert Enum.all?(list, fn s ->
                   is_binary(s) and String.length(s) >= 1 and String.length(s) <= 3
                 end)
      end
    end

    assert Enum.any?(values, fn v -> is_nil(v.tags) end)
    assert Enum.any?(values, fn v -> is_list(v.tags) end)
  end