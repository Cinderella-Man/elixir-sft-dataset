@impl GenServer
def handle_info({:flush_timer, key}, state) do
  case Map.fetch(state.batches, key) do
    # Requirement: Flush when timer fires and batch exists
    {:ok, _batch} ->
      {:noreply, do_flush(key, state)}

    # Ignore if already flushed via max_batch_size threshold
    :error ->
      {:noreply, state}
  end
end

@impl GenServer
def handle_info({:batch_done, callers, result}, state) do
  # Requirement: All callers in the same batch receive the same result
  Enum.each(callers, &GenServer.reply(&1, result))
  {:noreply, state}
end

@impl GenServer
def handle_info(_msg, state), do: {:noreply, state}