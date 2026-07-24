  @doc """
  Sets the gauge `name` to exactly `value`, overwriting any previous entry.

  Gauges are free to move up or down. Each `:ets.insert` is itself atomic,
  but unlike `increment/2`'s atomic read-modify-write a gauge set is a plain
  overwrite: concurrent sets to the same key are not coordinated (last-write
  wins), which is acceptable for gauge semantics.

  Returns `:ok`.
  """
  @spec gauge(term(), number()) :: :ok
  def gauge(name, value) do
    :ets.insert(@table, {name, value})
    :ok
  end