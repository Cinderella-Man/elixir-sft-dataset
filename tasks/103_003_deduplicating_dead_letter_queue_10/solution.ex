  defp public(e) do
    Map.take(e, [
      :id,
      :dedup_key,
      :message,
      :error_reason,
      :metadata,
      :occurrences,
      :retry_count,
      :first_seen,
      :last_seen
    ])
  end