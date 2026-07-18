  @spec count_above(term, number) :: {:ok, non_neg_integer}
  def count_above(name, threshold) when is_number(threshold) do
    GenServer.call(@default_name, {:count_above, name, threshold})
  end