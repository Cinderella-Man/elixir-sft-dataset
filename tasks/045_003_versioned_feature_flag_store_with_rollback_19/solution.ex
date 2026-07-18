  @doc """
  Turns `flag` fully off, recording a new version. Returns `:ok`.
  """
  @spec disable(atom()) :: :ok
  def disable(flag), do: GenServer.call(server(), {:write, flag, {:off}})