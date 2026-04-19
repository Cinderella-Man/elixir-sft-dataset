# Runs the user function, classifies the outcome.  Returns `{outcome, reply}`
# where outcome is `:ok` or `:error` (for window bookkeeping) and reply is
# the tuple the caller receives.
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
