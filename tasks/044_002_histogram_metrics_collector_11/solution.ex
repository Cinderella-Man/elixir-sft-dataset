  @doc """
  Returns a map of `%{name => total_count}` across every histogram.
  """
  @spec all() :: %{term() => non_neg_integer()}
  def all do
    :ets.foldl(
      fn
        {{name, :count}, v}, acc -> Map.put(acc, name, v)
        _other, acc -> acc
      end,
      %{},
      @table
    )
  end