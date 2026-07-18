  @spec validate_timestamp!(term(), atom()) :: :ok
  defp validate_timestamp!(ts, _op) when is_integer(ts) and ts > 0, do: :ok

  defp validate_timestamp!(ts, op) do
    raise ArgumentError,
          "timestamp for #{op} must be a positive integer, got: #{inspect(ts)}"
  end