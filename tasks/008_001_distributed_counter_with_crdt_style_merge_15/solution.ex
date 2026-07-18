  @spec validate_amount!(term(), atom()) :: :ok
  defp validate_amount!(amount, _op) when is_integer(amount) and amount > 0, do: :ok

  defp validate_amount!(amount, op) do
    raise ArgumentError,
          "amount for #{op} must be a positive integer, got: #{inspect(amount)}"
  end