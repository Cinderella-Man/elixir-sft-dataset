  defp handle_attempt_result(key, entry, result, state) do
    case result do
      {:ok, _} = success ->
        reply_all(entry.callers, success)
        {:noreply, Map.delete(state, key)}

      {:error, _} = error ->
        if entry.attempt < entry.retry_config.max_retries do
          next_attempt = entry.attempt + 1
          delay = compute_delay(next_attempt, entry.retry_config)
          Process.send_after(self(), {:retry_now, key}, delay)

          updated = %{entry | attempt: next_attempt, status: :waiting_retry}
          {:noreply, Map.put(state, key, updated)}
        else
          reply_all(entry.callers, error)
          {:noreply, Map.delete(state, key)}
        end
    end
  end