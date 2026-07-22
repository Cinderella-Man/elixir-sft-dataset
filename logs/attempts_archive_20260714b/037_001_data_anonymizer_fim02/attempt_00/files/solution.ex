  # :redact ----------------------------------------------------------------
  defp apply_rule(_value, :redact), do: "[REDACTED]"

  # :hash ------------------------------------------------------------------
  defp apply_rule(value, :hash) do
    value
    |> to_string()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # :mask ------------------------------------------------------------------
  defp apply_rule(value, :mask) do
    str = to_string(value)

    case String.length(str) do
      0 ->
        str

      1 ->
        "*"

      2 ->
        str

      len ->
        first  = String.at(str, 0)
        last   = String.at(str, len - 1)
        middle = String.duplicate("*", len - 2)
        first <> middle <> last
    end
  end

  # {:fake, seed} ----------------------------------------------------------
  defp apply_rule(value, {:fake, seed}) do
    generate_fake(to_string(value), seed)
  end