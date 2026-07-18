  @doc """
  Returns `flag`'s history as a list of `{version, state}` tuples in ascending
  version order, where `state` is `{:on}`, `{:off}`, or `{:percentage, n}`.
  Unknown flags return `[]`.
  """
  @spec history(atom()) :: [{pos_integer(), tuple()}]
  def history(flag) do
    hist_table()
    |> :ets.match_object({{flag, :_}, :_})
    |> Enum.map(fn {{^flag, v}, state} -> {v, state} end)
    |> Enum.sort_by(fn {v, _state} -> v end)
  end