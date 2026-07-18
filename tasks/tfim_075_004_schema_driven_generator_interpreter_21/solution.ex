  test "{:list, schema, opts} applies each documented default independently" do
    min_only =
      SchemaGenerators.from_schema({:list, :boolean, [min: 3]})
      |> Enum.take(300)
      |> Enum.map(&length/1)

    assert Enum.all?(min_only, fn len -> len >= 3 and len <= 10 end)
    assert 3 in min_only
    assert 10 in min_only

    max_only =
      SchemaGenerators.from_schema({:list, :boolean, [max: 2]})
      |> Enum.take(300)
      |> Enum.map(&length/1)

    assert Enum.all?(max_only, fn len -> len >= 0 and len <= 2 end)
    assert 0 in max_only
    assert 2 in max_only
  end