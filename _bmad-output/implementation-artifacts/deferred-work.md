# Deferred Work

## Deferred from: code review of 20-3-tpp-data-model-passive-measurement-engine (2026-03-27)

- `Int32` truncation for token counts in `TPPStorageService` — `sqlite3_bind_int(Int32(...))` used for `input_tokens`, `output_tokens`, `cache_create_tokens`, `cache_read_tokens`, `total_raw_tokens`, `message_count` columns. SQLite INTEGER is 64-bit but bind is 32-bit, risking silent data corruption for very large token counts. Pre-existing pattern from `storeBenchmarkResult` in Story 20.1 — fix should apply to all `sqlite3_bind_int` token columns in `TPPStorageService` at the same time.
