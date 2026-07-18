  @doc "Current number of slices."
  @spec num_slices(t()) :: pos_integer()
  def num_slices(%__MODULE__{slices: slices}), do: length(slices)