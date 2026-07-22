  @doc "Resumes execution from a previously produced journal."
  @spec resume(t(), context(), journal()) :: run_result()
  def resume(%__MODULE__{steps: steps}, context, journal)
      when is_map(context) and is_list(journal) do
    completed_names =
      for {:completed, name, _result} <- journal, do: name

    context2 =
      Enum.reduce(journal, context, fn
        {:completed, name, result}, acc -> Map.put(acc, name, result)
        _other, acc -> acc
      end)

    {done_steps, remaining} =
      Enum.split_with(steps, fn step -> step.name in completed_names end)

    # Seed the reverse-accumulator journal with the completed events so the
    # returned journal stays chronological once reversed.
    jrev0 =
      journal
      |> Enum.filter(fn
        {:completed, _n, _r} -> true
        _ -> false
      end)
      |> Enum.reverse()

    run(remaining, Enum.reverse(done_steps), context2, jrev0)
  end