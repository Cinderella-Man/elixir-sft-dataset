  @doc "Returns all series as a map keyed by `{name, labels_map}`."
  @spec all() :: %{{term(), map()} => number()}
  def all do
    :ets.foldl(
      fn {{name, norm}, value}, acc -> Map.put(acc, {name, Map.new(norm)}, value) end,
      %{},
      @table
    )
  end