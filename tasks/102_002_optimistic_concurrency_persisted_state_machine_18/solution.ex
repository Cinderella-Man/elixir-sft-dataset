  @doc """
  Attempts to transition `entity_id` via `event`, given `expected_version`.

  Checks are applied in order: not-started, stale-version, invalid-transition,
  then the successful transition. On success persists the new state, event, and
  version, updates in-memory state, and returns `{:ok, new_state, new_version}`.
  """
  @spec transition(GenServer.server(), String.t(), event(), non_neg_integer()) ::
          {:ok, state_name(), non_neg_integer()}
          | {:error, :not_found}
          | {:error, {:stale_version, non_neg_integer()}}
          | {:error, :invalid_transition}
          | {:error, {:db_error, term()}}
  def transition(server, entity_id, event, expected_version) do
    GenServer.call(server, {:transition, entity_id, event, expected_version})
  end