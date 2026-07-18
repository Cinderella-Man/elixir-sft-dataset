  @doc """
  Returns the effective value at `key_path` (a list of atoms), or `nil` if absent.
  """
  @spec get(GenServer.server(), [atom()]) :: term()
  def get(server, key_path) when is_list(key_path) do
    GenServer.call(server, {:get, key_path})
  end