  defp validate_identifier!(name) when is_binary(name) do
    unless Regex.match?(@valid_identifier, name) do
      raise ArgumentError,
            "invalid identifier #{inspect(name)}. Must match /[a-zA-Z_][a-zA-Z0-9_]*/"
    end

    :ok
  end

  defp validate_identifier!(other) do
    raise ArgumentError, "expected identifier to be a string, got: #{inspect(other)}"
  end