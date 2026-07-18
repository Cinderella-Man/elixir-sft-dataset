  @doc """
  Records a numeric `value` into series `name`, timestamped with the current
  clock time. Returns `:ok`.
  """
  @spec record(term, number) :: :ok
  def record(name, value) when is_number(value) do
    GenServer.call(@default_name, {:record, name, value})
  end