  @spec to_status_info(service()) :: status_info()
  defp to_status_info(service) do
    %{
      status: reported_status(service),
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures,
      maintenance_ends_at: service.maintenance_ends_at
    }
  end