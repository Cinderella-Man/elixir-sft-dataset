  defp type_kind(v) when is_integer(v), do: :integer
  defp type_kind(v) when is_float(v), do: :float
  defp type_kind(v) when is_boolean(v), do: :boolean
  defp type_kind(v) when is_atom(v), do: :atom
  defp type_kind(v) when is_binary(v), do: :binary
  defp type_kind(v) when is_list(v), do: :list
  defp type_kind(v) when is_map(v), do: :map
  defp type_kind(_v), do: :other