  # Runs one check, updating failure count/status and firing notify on an
  # `:up` -> `:down` transition. Returns `{updated_service, resulting_status}`.
  @spec run_check(service(), term()) :: {service(), status()}
  defp run_check(service, name) do
    case service.check_func.() do
      :ok ->
        {%{service | failures: 0, status: :up}, :up}

      {:error, reason} ->
        failures = service.failures + 1

        if service.status == :up and failures >= service.threshold do
          service.notify.(name, reason)
          {%{service | failures: failures, status: :down}, :down}
        else
          {%{service | failures: failures}, service.status}
        end
    end
  end