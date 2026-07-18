  @spec hash(term()) :: String.t()
  defp hash(value) do
    data = if is_binary(value), do: value, else: inspect(value)
    digest = Base.encode16(:crypto.hash(:sha256, data), case: :lower)
    "sha256:" <> digest
  end