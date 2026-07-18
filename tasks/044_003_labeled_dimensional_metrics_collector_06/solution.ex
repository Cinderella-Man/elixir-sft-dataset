  @doc "Sets the `{name, %{}}` gauge to exactly `value`."
  @spec gauge(term(), number()) :: :ok
  def gauge(name, value), do: gauge(name, %{}, value)

  @doc "Sets the `{name, labels}` gauge to exactly `value`."
  @spec gauge(term(), map(), number()) :: :ok
  def gauge(name, labels, value) when is_map(labels) do
    :ets.insert(@table, {key(name, labels), value})
    :ok
  end