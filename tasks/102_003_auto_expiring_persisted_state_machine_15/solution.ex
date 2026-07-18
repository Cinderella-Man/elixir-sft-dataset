  @spec maybe_schedule(state(), String.t(), non_neg_integer() | nil) :: :ok
  defp maybe_schedule(:pending, entity_id, ttl) when is_integer(ttl) do
    Process.send_after(self(), {:check_expiry, entity_id}, ttl)
    :ok
  end

  defp maybe_schedule(_state, _entity_id, _ttl), do: :ok