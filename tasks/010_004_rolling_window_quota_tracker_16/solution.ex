  @doc """
  Clears all usage history for `key`.

  Returns `:ok` always.
  """
  @spec reset(server(), key()) :: :ok
  def reset(server, key) do
    GenServer.call(server, {:reset, key})
  end