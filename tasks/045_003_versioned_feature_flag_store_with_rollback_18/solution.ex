  @doc """
  Turns `flag` fully on, recording a new version. Returns `:ok`.
  """
  @spec enable(atom()) :: :ok
  def enable(flag), do: GenServer.call(server(), {:write, flag, {:on}})