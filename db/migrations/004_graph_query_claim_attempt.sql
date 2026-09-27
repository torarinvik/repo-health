-- Return the durable attempt number with a graph-query lease so the worker can
-- apply the same fenced retry transition used by operator-driven retries.

BEGIN;

CREATE FUNCTION rh_claim_graph_query_job_with_attempt(
    p_worker_id text,
    p_now timestamptz,
    p_lease_seconds integer,
    p_job_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_claim jsonb;
    v_attempt_count integer;
BEGIN
    v_claim := rh_claim_graph_query_job(p_worker_id, p_now, p_lease_seconds, p_job_id);
    IF v_claim->>'status' <> 'claimed' THEN
        RETURN v_claim;
    END IF;

    SELECT j.attempt_count INTO v_attempt_count
    FROM job AS j
    WHERE j.id = (v_claim->>'job_id')::uuid
      AND j.kind = 'graph_query'
      AND j.state = 'running'
      AND j.fencing_token = (v_claim->>'fencing_token')::bigint
      AND j.lease_expires_at > p_now;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'claimed graph query attempt changed before worker handoff';
    END IF;

    RETURN v_claim || jsonb_build_object('attempt_count', v_attempt_count);
END;
$$;

COMMIT;
