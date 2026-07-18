  @impl true
  def init(opts) do
    sensitive =
      opts
      |> Keyword.get(:sensitive_keys, [])
      |> Enum.map(&normalize_key/1)
      |> MapSet.new()

    state = %{sensitive: sensitive, patterns: [], keys_masked: 0, patterns_applied: 0}
    {:ok, state}
  end