  @doc """
  Convenience wrapper equivalent to `finalize(partial(csv, opts))`.
  """
  @spec infer_string(String.t(), keyword()) :: schema()
  def infer_string(csv, opts \\ []) do
    csv
    |> partial(opts)
    |> finalize()
  end