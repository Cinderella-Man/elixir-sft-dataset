  @doc """
  Returns the current integer version of `flag`. The first write yields `1` and
  every subsequent write increments it. Unknown flags return `0`.
  """
  @spec version(atom()) :: non_neg_integer()
  def version(flag) do
    case :ets.lookup(state_table(), flag) do
      [{^flag, _state, v}] -> v
      [] -> 0
    end
  end