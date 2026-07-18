  defp run_stage({name, fun, retries, backoff}, value) do
    attempt(name, fun, value, retries, backoff, 0, 0)
  end