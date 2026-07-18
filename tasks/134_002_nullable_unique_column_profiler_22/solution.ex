  @doc """
  Infers a per-column schema profile from the given CSV `csv` string.

  Returns a map of column name to `%{type: t, nullable: n, unique: u}`.
  See the module documentation for the supported options (`:headers` and
  `:sample_rows`).
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
    |> Map.new(fn {name, index} -> {name, profile(sampled, index)} end)
  end