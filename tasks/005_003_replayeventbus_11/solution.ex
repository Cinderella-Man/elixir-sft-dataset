  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {{_pid, topics}, monitors} ->
        new_topics =
          Enum.reduce(topics, state.topics, fn topic, acc ->
            case Map.get(acc, topic) do
              nil ->
                acc

              t ->
                Map.put(acc, topic, %{t | subs: Enum.reject(t.subs, &(&1.ref == ref))})
            end
          end)

        {:noreply, %{state | topics: new_topics, monitors: monitors}}
    end
  end

  def handle_info(:cleanup, state) do
    now = state.clock.()

    new_topics =
      Enum.reduce(state.topics, %{}, fn {name, t}, acc ->
        fresh = evict_expired(t, now, state.history_ttl_ms)

        # Drop topics with empty history AND no subscribers.
        if fresh.history == [] and fresh.subs == [] do
          acc
        else
          Map.put(acc, name, fresh)
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | topics: new_topics}}
  end

  def handle_info(_msg, state), do: {:noreply, state}