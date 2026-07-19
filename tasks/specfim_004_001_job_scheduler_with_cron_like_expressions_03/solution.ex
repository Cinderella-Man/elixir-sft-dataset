  @spec register(server(), job_name(), cron_expression(), mfa_tuple()) ::
          :ok | {:error, :invalid_cron | :already_exists}