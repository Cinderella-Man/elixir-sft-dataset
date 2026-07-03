  # Returns whether a session's sliding deadline has passed.
  @spec expired?(session(), integer(), non_neg_integer()) :: boolean()
  defp expired?(session, now, timeout_ms) do
    now - session.last_active >= timeout_ms
  end