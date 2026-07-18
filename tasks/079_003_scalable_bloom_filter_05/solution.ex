  @doc "Returns `true` if `item` is present in any slice."
  @spec member?(t(), term()) :: boolean()
  def member?(%__MODULE__{slices: slices}, item) do
    Enum.any?(slices, fn slice -> slice_member?(slice, item) end)
  end