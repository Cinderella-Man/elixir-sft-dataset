  @doc """
  Records `amount` events (default 1) for `name` at the current second.

  Atomically bumps the per-second bucket via `:ets.update_counter/4`. Returns
  `:ok`.
  """
  @spec increment(term(), non_neg_integer()) :: :ok
  def increment(name, amount \\ 1) when is_integer(amount) and amount >= 0 do
    second = now()
    key = {name, second}
    :ets.update_counter(@table, key, {2, amount}, {key, 0})
    :ok
  end