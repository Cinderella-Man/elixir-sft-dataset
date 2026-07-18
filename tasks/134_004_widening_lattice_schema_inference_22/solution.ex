  @doc """
  Infers a schema from CSV `csv` given as a string.

  Returns a map of `%{"column_name" => type}` where each type is the join of
  the column's distinct non-null cell categories in the widening lattice.

  Options: `:headers` (boolean, default `true`) and `:sample_rows`
  (positive integer, default `100`).
  """
  @spec infer_string(String.t(), keyword()) :: schema()
  def infer_string(csv, opts \\ []) when is_binary(csv) do
    headers? = Keyword.get(opts, :headers, true)
    sample = Keyword.get(opts, :sample_rows, 100)

    records = parse_csv(csv)
    {names, data_rows} = split_records(records, headers?)
    sampled = Enum.take(data_rows, sample)
    names = names || default_names(sampled)

    names
    |> Enum.with_index()
    |> Map.new(fn {name, index} ->
      {name, resolve(column_cells(sampled, index))}
    end)
  end