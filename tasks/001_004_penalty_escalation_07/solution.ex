  defp empty_entry do
    %{timestamps: [], strikes: 0, last_strike_at: nil, cooldown_end: nil, window_ms: nil}
  end