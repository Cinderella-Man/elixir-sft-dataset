  defp resolve_opts(opts) do
    global = Keyword.get(opts, :list_strategy, :replace)

    per_key =
      opts
      |> Keyword.get(:list_strategies, %{})
      |> Map.new(fn {path, strat} -> {normalise_path(path), strat} end)

    locked = Enum.map(Keyword.get(opts, :locked, []), &normalise_path/1)

    %{global_list_strategy: global, per_key_strategies: per_key, locked_paths: locked}
  end