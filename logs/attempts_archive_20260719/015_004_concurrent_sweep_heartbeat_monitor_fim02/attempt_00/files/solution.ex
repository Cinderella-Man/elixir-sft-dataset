  # Spawn one probe process per service (all before waiting), then gather.
  @spec run_sweep(map()) :: %{optional(term()) => :ok | :error}
  defp run_sweep(services) do
    server = self()

    refs =
      Enum.map(services, fn {name, svc} ->
        ref = make_ref()
        probe = svc.probe
        spawn(fn -> send(server, {:probe_result, ref, run_probe(probe)}) end)
        {ref, name}
      end)

    gather(refs, %{})
  end