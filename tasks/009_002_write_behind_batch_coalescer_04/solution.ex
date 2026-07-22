  def handle_info({:flush_timer, key, gen}, state) do
    case Map.fetch(state.batches, key) do
      # Requirement: flush when the timer fires and it is THIS batch's timer.
      {:ok, %{gen: ^gen}} ->
        {:noreply, do_flush(key, state)}

      # A ref mismatch is a stale timer for an earlier, already-flushed batch
      # generation; :error means the batch flushed and no successor exists.
      # Both are ignored harmlessly.
      _ ->
        {:noreply, state}
    end
  end
