  @doc """
  Discards all samples for series `name`. Returns `:ok`.
  """
  @spec reset(term) :: :ok
  def reset(name) do
    GenServer.call(@default_name, {:reset, name})
  end