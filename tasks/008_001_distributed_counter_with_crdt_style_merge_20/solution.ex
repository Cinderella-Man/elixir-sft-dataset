  @doc """
  Merges a remote PN-Counter state into the local state.

  `remote_state` must be a map of the form `%{p: %{...}, n: %{...}}` —
  i.e. the structure returned by `Counter.state/1`.

  For each node, the merge takes the **maximum** of the local and remote
  values for both `p` and `n` independently. This ensures the merge is
  idempotent, commutative, and associative.

  Returns `:ok`.
  """
  @spec merge(server(), pn_state()) :: :ok
  def merge(server, %{p: p, n: n} = _remote_state)
      when is_map(p) and is_map(n) do
    GenServer.call(server, {:merge, %{p: p, n: n}})
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must be a map with :p and :n keys, got: #{inspect(invalid)}"
  end