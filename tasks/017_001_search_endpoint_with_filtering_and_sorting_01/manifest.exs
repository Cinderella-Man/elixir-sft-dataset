# Task 017 requires Postgres-only SQL (ILIKE); SQLite rejects it.
# The harness dispatches via Plug.Test straight to the Router (no ConnCase),
# so the tier-B archetype can no longer be inferred from the harness — state
# it explicitly: the kit compile + Repo/migrations boot are still required.
%{
  archetype: :phoenix_conncase,
  prefix: "MyApp",
  web_prefix: "MyAppWeb",
  otp_app: :my_app,
  db: :postgres
}
