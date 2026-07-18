  @doc "Increments the `{name, labels}` counter by `amount` (default 1)."
  @spec increment(term()) :: :ok
  def increment(name), do: increment(name, %{}, 1)

  @spec increment(term(), map() | non_neg_integer()) :: :ok
  def increment(name, labels) when is_map(labels), do: increment(name, labels, 1)
  def increment(name, amount) when is_integer(amount), do: increment(name, %{}, amount)

  @spec increment(term(), map(), non_neg_integer()) :: :ok
  def increment(name, labels, amount)
      when is_map(labels) and is_integer(amount) and amount >= 0 do
    key = key(name, labels)
    :ets.update_counter(@table, key, {2, amount}, {key, 0})
    :ok
  end