  @doc """
  Load the latest persisted state and approval count for `entity_id`.

  If no record exists, the entity starts in `:draft` with an approval
  count of `0`. Returns `{:ok, current_state, approval_count}`.
  """
  @spec start(server(), String.t()) :: {:ok, state_name(), non_neg_integer()}
  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end