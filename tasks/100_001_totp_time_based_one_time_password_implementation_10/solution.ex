  defp dec!(c) when c in ?A..?Z, do: c - ?A
  defp dec!(c) when c in ?2..?7, do: c - ?2 + 26
  defp dec!(c), do: raise(ArgumentError, "invalid base32 character: #{<<c>>}")