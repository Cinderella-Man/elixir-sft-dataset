defp process_attempt(job, now) do
  outcome = safe_execute(job.mfa)
  attempts = job.attempts_so_far + 1

  case outcome do
    :success ->
      %{job | status: :completed, attempts_so_far: attempts, next_attempt_at: now}

    :failure when attempts >= job.max_attempts ->
      %{job | status: :dead, attempts_so_far: attempts, next_attempt_at: now}

    :failure ->
      delay_ms = round(job.base_delay_ms * :math.pow(job.backoff_factor, attempts - 1))
      next = NaiveDateTime.add(now, delay_ms, :millisecond)

      %{
        job
        | status: :pending,
          attempts_so_far: attempts,
          next_attempt_at: next
      }
  end
end
