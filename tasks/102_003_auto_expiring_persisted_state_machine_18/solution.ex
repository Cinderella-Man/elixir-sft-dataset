  @doc """
  Loads the latest persisted state for `entity_id` and tracks it in memory.

  If no record exists the entity starts in `:pending`. When a `:pending_ttl_ms`
  was configured and the loaded state is `:pending`, an expiry check is
  scheduled. Always returns `{:ok, current_state}`.
  """
  @spec start(GenServer.server(), String.t()) :: {:ok, state()}
  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end