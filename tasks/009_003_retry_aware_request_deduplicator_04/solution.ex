defp compute_delay(attempt, %{base_delay_ms: base, max_delay_ms: max_d}) do
  # attempt is 1-based here (first retry = attempt 1)
  raw = base * Integer.pow(2, attempt - 1)
  min(raw, max_d)
end