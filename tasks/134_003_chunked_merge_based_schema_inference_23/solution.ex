  @doc """
  Resolve a partial into a schema map `%{"column_name" => :inferred_type}`.

  Column names come from `:names` when present, otherwise positional names
  `"column_1"`..`"column_ncols"` are generated from `:ncols`.
  """
  @spec finalize(partial()) :: schema()
  def finalize(%{names: names, ncols: ncols, categories: categories}) do
    resolved_names = names || Enum.map(1..ncols//1, fn i -> "column_#{i}" end)

    resolved_names
    |> Enum.with_index()
    |> Map.new(fn {name, index} ->
      {name, resolve(Map.get(categories, index, MapSet.new()))}
    end)
  end