  # Returns `{:ok | :error, reply}` where the atom is the outcome for state
  # bookkeeping and `reply` is what the caller sees.
  defp execute_and_classify(func) do
    try do
      case func.() do
        {:ok, _value} = ok -> {:ok, ok}
        {:error, _reason} = err -> {:error, err}
        other -> {:error, {:error, {:unexpected_return, other}}}
      end
    rescue
      exception -> {:error, {:error, exception}}
    end
  end