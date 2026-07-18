  @doc """
  Computes the requested `percentile` (a float in `0.0..1.0`) over the currently
  live samples of series `name`.

  Returns `{:ok, value}` where `value` is one of the recorded samples, or
  `{:error, :empty}` when the series has no live samples.
  """
  @spec query(term, float) :: {:ok, number} | {:error, :empty}
  def query(name, percentile)
      when is_number(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(@default_name, {:query, name, percentile})
  end