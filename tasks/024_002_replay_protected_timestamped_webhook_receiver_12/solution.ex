  @doc """
  Parses a header like `"t=123,v1=abc"` into a map of string keys/values.

  Returns `%{}` for any non-binary input.
  """
  @spec parse(term()) :: %{optional(String.t()) => String.t()}
  def parse(header) when is_binary(header) do
    header
    |> String.split(",", trim: true)
    |> Enum.reduce(%{}, fn part, acc ->
      case String.split(part, "=", parts: 2) do
        [k, v] -> Map.put(acc, String.trim(k), String.trim(v))
        _ -> acc
      end
    end)
  end

  def parse(_), do: %{}