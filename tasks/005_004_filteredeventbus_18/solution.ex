  @doc """
  Pure evaluation of `filter` against `event`, outside any GenServer.
  Returns `true | false`, or `{:error, :invalid_filter}` if the filter fails
  structural validation.
  """
  @spec test_filter(list(), term()) :: boolean() | {:error, :invalid_filter}
  def test_filter(filter, event) when is_list(filter) do
    if valid_filter?(filter) do
      eval_filter(filter, event)
    else
      {:error, :invalid_filter}
    end
  end