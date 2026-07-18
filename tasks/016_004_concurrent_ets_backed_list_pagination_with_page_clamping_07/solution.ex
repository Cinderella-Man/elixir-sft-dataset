  @doc """
  Return the number of stored items.
  """
  @spec count(:ets.tid()) :: non_neg_integer()
  def count(table), do: :ets.info(table, :size)