  @doc """
  Sets the gauge `name` to exactly `value`, overwriting any previous entry.

  Gauges are free to move up or down. Unlike `increment/2` this write
  is not atomic with respect to concurrent gauge writes for the same key,
  which is acceptable for gauge semantics (last-write wins).

  Returns `:ok`.
  """
  @spec gauge(term(), number()) :: :ok
  def gauge(name, value) do
    :ets.insert(@table, {name, value})
    :ok
  end