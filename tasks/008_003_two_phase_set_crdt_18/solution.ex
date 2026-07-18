  @doc """
  Merges a remote 2P-Set state into the local state.

  `remote_state` must be a map of the form `%{added: MapSet, removed: MapSet}`.

  The merge computes the union of the add-sets and separately the union of the
  remove-sets. This ensures the merge is idempotent, commutative, and associative.

  Returns `:ok`.
  """
  @spec merge(server(), tp_state()) :: :ok
  def merge(server, %{added: added, removed: removed} = _remote_state) do
    GenServer.call(server, {:merge, %{added: MapSet.new(added), removed: MapSet.new(removed)}})
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must be a map with :added and :removed keys, got: #{inspect(invalid)}"
  end