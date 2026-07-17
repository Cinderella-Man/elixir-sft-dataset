  defp resolve(_pid, _field, _value, :redact), do: "[REDACTED]"

  defp resolve(_pid, _field, value, :hash) do
    :crypto.hash(:sha256, to_string(value)) |> Base.encode16(case: :lower)
  end

  defp resolve(pid, field, value, {:pseudonym, prefix}) do
    GenServer.call(pid, {:pseudonym, field, value, prefix})
  end