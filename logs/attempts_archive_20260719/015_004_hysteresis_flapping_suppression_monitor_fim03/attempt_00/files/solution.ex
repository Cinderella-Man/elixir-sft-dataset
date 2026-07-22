  @spec run_check(term(), map()) :: map()
  defp run_check(name, service) do
    case service.check_func.() do
      :ok -> handle_ok(name, service)
      {:error, _reason} -> handle_error(name, service)
    end
  end