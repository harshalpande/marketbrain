-- Candidate redacted audit views. Isolated recovery rehearsal only; NOT a Flyway migration.
-- Grants are applied to a disposable non-owner role by the verifier, never to PUBLIC.
CREATE VIEW paper_review_audit AS
SELECT portfolio_id, cash, reserved, revision FROM paper_ledger_account;

CREATE VIEW paper_delivery_audit AS
SELECT d.proposal_id, d.state, d.created_at, d.attempted_at,
       (p.receipt IS NOT NULL) AS reviewed
FROM paper_approval_delivery d JOIN paper_approval_proposal p ON p.id=d.proposal_id;
