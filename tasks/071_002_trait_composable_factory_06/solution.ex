  @doc "Returns the next value for the named sequence."
  @spec sequence(term(), (pos_integer() -> value)) :: value when value: var
  def sequence(name, formatter_fn) when is_function(formatter_fn, 1) do
    ensure_agent_started()

    n =
      Agent.get_and_update(@agent, fn counters ->
        next = Map.get(counters, name, 0) + 1
        {next, Map.put(counters, name, next)}
      end)

    formatter_fn.(n)
  end