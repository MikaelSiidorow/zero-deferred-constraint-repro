CREATE TABLE swap_test (
    id           SERIAL PRIMARY KEY,
    workspace_id INTEGER NOT NULL,
    user_id      INTEGER NOT NULL,
    target_id    INTEGER NOT NULL,
    kind         TEXT    NOT NULL CHECK (kind IN ('primary', 'secondary'))
);

CREATE UNIQUE INDEX swap_test_workspace_user_kind_key
    ON swap_test (workspace_id, user_id, kind);

-- Deferred so a swap inside a transaction doesn't trip on the transient
-- mid-statement duplicate.
ALTER TABLE swap_test
    ADD CONSTRAINT swap_test_workspace_user_target_unique
        UNIQUE (workspace_id, user_id, target_id) DEFERRABLE INITIALLY DEFERRED;

INSERT INTO swap_test (workspace_id, user_id, target_id, kind) VALUES
    (1, 100, 200, 'primary'),
    (1, 100, 300, 'secondary');
