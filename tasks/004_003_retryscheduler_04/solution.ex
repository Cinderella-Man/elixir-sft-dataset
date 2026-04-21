defp validate_opts(opts) do
  max_attempts = Keyword.get(opts, :max_attempts, 3)
  base_delay_ms = Keyword.get(opts, :base_delay_ms, 1_000)
  backoff_factor = Keyword.get(opts, :backoff_factor, 2.0)

  cond do
    not is_integer(max_attempts) or max_attempts < 1 -> :error
    not is_integer(base_delay_ms) or base_delay_ms < 0 -> :error
    not is_number(backoff_factor) or backoff_factor < 1.0 -> :error
    true -> {:ok, max_attempts, base_delay_ms, backoff_factor * 1.0}
  end
end
