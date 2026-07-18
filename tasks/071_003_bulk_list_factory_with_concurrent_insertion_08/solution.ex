  @spec merge_overrides(struct(), overrides()) :: struct()
  defp merge_overrides(base, []), do: base
  defp merge_overrides(base, overrides), do: struct(base, overrides)