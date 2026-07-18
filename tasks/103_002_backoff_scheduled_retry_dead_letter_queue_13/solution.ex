  defp public(e) do
    Map.take(e, [
      :id,
      :message,
      :error_reason,
      :metadata,
      :retry_count,
      :status,
      :next_retry_at,
      :pushed_at
    ])
  end