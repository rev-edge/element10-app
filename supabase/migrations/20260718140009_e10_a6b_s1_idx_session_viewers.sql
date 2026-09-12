-- A6b Step 1 EXPAND — standalone UNIQUE INDEX CONCURRENTLY on (organization_id, session_id, user_id). Own non-transactional step (ADR §12 s2).
-- Recovery: a failed CONCURRENTLY leaves an INVALID index; detect (indisvalid=false), DROP INDEX, re-run this step.
create unique index concurrently if not exists e10_session_viewers_org_uq on public.e10_session_viewers (organization_id, session_id, user_id);
