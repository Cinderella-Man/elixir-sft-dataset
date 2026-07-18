  @doc """
  Infers the schema from CSV `csv` given as a string.

  Options:

    * `:headers` (boolean, default `true`) — when `true` the first record is
      the header row supplying column names; when `false` all records are data
      and columns are named `"column_1"`, `"column_2"`, ….
    * `:sample_rows` (positive integer, default `100`) — infer from at most the
      first N data rows.
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
      {name, resolve_column(column_cells(sampled, index))}
    end)
  end