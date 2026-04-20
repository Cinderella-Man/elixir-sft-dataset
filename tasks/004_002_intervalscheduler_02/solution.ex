# Drift-free: next_run = started_at + N*interval_s for smallest N>=1 such
# that result > now.  Equivalently:
#
#   elapsed = now - started_at
#   N = max(1, div(elapsed, interval_s) + 1)
#
# Examples with started_at=0, interval=10:
#   now=0   -> elapsed=0,  N=max(1, 0+1)=1, next=10   (first run)
#   now=9   -> elapsed=9,  N=max(1, 0+1)=1, next=10
#   now=10  -> elapsed=10, N=max(1, 1+1)=2, next=20   (boundary just hit)
#   now=25  -> elapsed=25, N=max(1, 2+1)=3, next=30   (no catch-up replay)
defp compute_next_run(started_at, interval_s, now) do
  elapsed = NaiveDateTime.diff(now, started_at, :second)
  n = max(1, div(elapsed, interval_s) + 1)
  NaiveDateTime.add(started_at, n * interval_s, :second)
end
