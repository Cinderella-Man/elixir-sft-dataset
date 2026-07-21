  # Returns `{:ok | :error, reply}` where the atom is the outcome for state
  # bookkeeping and `reply` is what the caller sees.
  defp execute_and_classify(func) do
    try do
      case func.() do
        {:ok, _value} = ok -> {:ok, ok}
        {:error, _reason} = err -> {:error, err}
        # Anything that is not {:ok, _} counts as a failure for the state
        # bookkeeping, but the caller still sees exactly what func returned.
        other -> {:error, other}
      end
    rescue
      exception -> {:error, {:error, exception}}
    end
  end
