  @doc """
  Parse a CSV fragment into an opaque partial inference state (a plain map).

  With `headers: true` (the default) the first record supplies column names;
  with `headers: false` every record is data and columns are positional. A
  fragment with no records at all has `:names` of `nil`, making it a neutral
  element for `merge/2`. The returned map has `:names`, `:ncols`, and
  `:categories` keys.
  """
  @spec partial(String.t(), keyword()) :: partial()
  def partial(csv, opts \\ []) when is_binary(csv) do
    headers? = Keyword.get(opts, :headers, true)

    records = parse_csv(csv)
    {names, data_rows} = split_records(records, headers?)

    ncols =
      [length(names || [])]
      |> Kernel.++(Enum.map(data_rows, &length/1))
      |> Enum.max()

    %{names: names, ncols: ncols, categories: build_categories(data_rows)}
  end