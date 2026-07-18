  @doc """
  Merges a remote LWW-Element-Set state into the local state.

  `remote_state` must be a map of the form `%{adds: %{...}, removes: %{...}}`
  — i.e. the structure returned by `LWWSet.state/1`.

  For each element, the merge takes the **maximum** of the local and remote
  timestamps for both `adds` and `removes` independently. This ensures the
  merge is idempotent, commutative, and associative.

  Returns `:ok`.
  """
  @spec merge(server(), lww_state()) :: :ok
  def merge(server, %{adds: adds, removes: removes} = _remote_state)
      when is_map(adds) and is_map(removes) do
    GenServer.call(server, {:merge, %{adds: adds, removes: removes}})
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must be a map with :adds and :removes keys, got: #{inspect(invalid)}"
  end