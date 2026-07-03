  defp fetch_live_session(sessions, session_id, now, timeout_ms) do
    case Map.fetch(sessions, session_id) do
      {:ok, session} ->
        if expired?(session, now, timeout_ms), do: :expired, else: {:ok, session}

      :error ->
        :missing
    end
  end