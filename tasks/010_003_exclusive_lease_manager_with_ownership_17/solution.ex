  @doc """
  Unconditionally removes any lease on `resource` regardless of owner.

  Always returns `:ok`. This is an administrative operation.
  """
  @spec force_release(server(), resource()) :: :ok
  def force_release(server, resource) do
    GenServer.call(server, {:force_release, resource})
  end