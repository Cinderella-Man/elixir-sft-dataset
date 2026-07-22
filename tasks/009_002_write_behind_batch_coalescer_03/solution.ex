  @impl GenServer
  def handle_call({:submit, key, item, flush_fn, max_batch_size}, from, state) do
    case Map.fetch(state.batches, key) do
      :error ->
        # Requirement: First submit for a key starts the flush timer
        # The batch generation rides in the message: a stale timer whose batch
        # already flushed (threshold path) can never fire a SUCCESSOR batch —
        # key-presence alone cannot tell two generations apart. The send_after
        # ref is kept separately so threshold flushes still cancel the timer.
        gen = make_ref()

        timer_ref =
          Process.send_after(self(), {:flush_timer, key, gen}, state.flush_interval_ms)

        batch = %{
          # Prepend is O(1)
          items: [item],
          callers: [from],
          flush_fn: flush_fn,
          max_batch_size: max_batch_size,
          timer_ref: timer_ref,
          gen: gen
        }

        new_state = put_in(state, [:batches, key], batch)

        if max_batch_size <= 1 do
          {:noreply, do_flush(key, new_state)}
        else
          {:noreply, new_state}
        end

      {:ok, batch} ->
        updated_batch = %{
          batch
          | # Prepend is O(1)
            items: [item | batch.items],
            callers: [from | batch.callers]
        }

        new_state = put_in(state, [:batches, key], updated_batch)

        if length(updated_batch.items) >= updated_batch.max_batch_size do
          {:noreply, do_flush(key, new_state)}
        else
          {:noreply, new_state}
        end
    end
  end
