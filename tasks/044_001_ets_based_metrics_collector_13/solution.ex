  @doc """
  Resets the metric `name` to `0`.

  Works for both counters and gauges. If `name` does not exist it is
  created with the value `0`.

  Returns `:ok`.
  """
  @spec reset(term()) :: :ok
  def reset(name) do
    :ets.insert(@table, {name, 0})
    :ok
  end