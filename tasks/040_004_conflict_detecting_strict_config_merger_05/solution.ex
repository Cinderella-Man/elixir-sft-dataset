  defp resolve_opts(opts) do
    per_key =
      opts
      |> Keyword.get(:list_strategies, %{})
      |> Map.new(fn {path, strat} -> {normalise_path(path), strat} end)

    %{
      strict: Keyword.get(opts, :strict, false),
      global_list_strategy: Keyword.get(opts, :list_strategy, :replace),
      per_key_strategies: per_key,
      locked_paths: Enum.map(Keyword.get(opts, :locked, []), &normalise_path/1),
      required: Enum.map(Keyword.get(opts, :required, []), &normalise_path/1)
    }
  end