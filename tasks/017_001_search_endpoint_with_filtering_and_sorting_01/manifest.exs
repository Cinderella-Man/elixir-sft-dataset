# Task 017 requires Postgres-only SQL (ILIKE); SQLite rejects it. Marked for the
# (deferred) Postgres kit — the evaluator skips-with-reason until that exists (S4-D2).
%{db: :postgres}
