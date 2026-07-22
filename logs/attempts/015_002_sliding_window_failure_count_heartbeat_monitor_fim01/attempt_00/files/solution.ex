  @spec probe_and_notify(term(), map()) :: {map(), status()}
  defp probe_and_notify(name, service) do
    outcome = run_probe(service.probe)
    results = Enum.take([outcome | service.results], service.window)
    failures = Enum.count(results, &(&1 == :fail))
    new_status = if failures >= service.threshold, do: :down, else: :up

    if new_status != service.status do
      service.on_change.(name, new_status)
    end

    {%{service | results: results, status: new_status}, new_status}
  end