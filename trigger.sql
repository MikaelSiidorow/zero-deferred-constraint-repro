-- Swap target_id between the two rows. Postgres defers the unique check to
-- COMMIT; Zero's SQLite replica checks each statement and crashes on the
-- first UPDATE's transient duplicate.
BEGIN;
UPDATE swap_test SET target_id = 300 WHERE kind = 'primary'   AND workspace_id = 1 AND user_id = 100;
UPDATE swap_test SET target_id = 200 WHERE kind = 'secondary' AND workspace_id = 1 AND user_id = 100;
COMMIT;
