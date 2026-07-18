  @spec to_status_info(service()) :: status_info()
  defp to_status_info(service) do
    %{
      status: service.status,
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures,
      check_in_flight: service.task_ref != nil
    }
  end