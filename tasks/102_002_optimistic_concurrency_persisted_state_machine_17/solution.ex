  @doc """
  Loads the latest persisted state and version for `entity_id` from the database.

  If no record exists, the entity starts in the `:pending` state at version 0.
  Returns `{:ok, current_state, current_version}`.
  """
  @spec start(GenServer.server(), String.t()) :: {:ok, state_name(), non_neg_integer()}
  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end