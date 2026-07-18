  @doc """
  Merges a remote OR-Set state into the local state.

  `remote_state` must be a map with `:entries`, `:tombstones`, and `:clock` keys.

  Returns `:ok`.
  """
  @spec merge(server(), or_state()) :: :ok
  def merge(server, %{entries: entries, tombstones: tombstones, clock: clock} = _remote)
      when is_map(entries) and is_map(clock) do
    GenServer.call(
      server,
      {:merge, %{entries: entries, tombstones: MapSet.new(tombstones), clock: clock}}
    )
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must have :entries, :tombstones, :clock keys, got: #{inspect(invalid)}"
  end