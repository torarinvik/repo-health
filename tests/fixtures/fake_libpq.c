#include <stdlib.h>
#include <stdio.h>
#include <string.h>

typedef struct { int marker; } FakeConnection;
typedef struct { int status; int rows; int columns; const char *value; } FakeResult;

static FakeConnection connection = { 1 };
static FakeResult result = { 2, 1, 1, "t" };
static const char *claim_cells[3] = {
    "00000000-0000-0000-0000-000000000004", "5", "2026-01-01 00:02:00+00"
};
static const char *claim_collection_cells[3] = {
    "00000000-0000-0000-0000-00000000000a", "1", "2026-01-01 00:02:00+00"
};
static const char *ingest_claim_cells[3] = {
    "00000000-0000-0000-0000-000000000021", "1", "2026-09-21 00:04:00+00"
};
static const char *evidence_references_json =
    "{\"storage_keys\":[\"fnv1a64:f5e19178d3ff184e\"],\"invalid_count\":0,\"truncated\":false,\"count\":1}";
static const char *evidence_references_invalid_json =
    "{\"storage_keys\":[\"fnv1a64:f5e19178d3ff184e\"],\"invalid_count\":1,\"truncated\":false,\"count\":1}";
static const char *evidence_references_truncated_json =
    "{\"storage_keys\":[\"fnv1a64:f5e19178d3ff184e\"],\"invalid_count\":0,\"truncated\":true,\"count\":1}";
static const char *evidence_references_unsorted_json =
    "{\"storage_keys\":[\"fnv1a64:f5e19178d3ff184e\",\"fnv1a64:0000000000000000\"],\"invalid_count\":0,\"truncated\":false,\"count\":2}";

void *PQconnectdbParams(const char *const *keywords, const char *const *values, int expand_dbname) {
    const char *marker = getenv("RH_FAKE_PG_CONNECT_MARK");
    if (marker != NULL) {
        FILE *stream = fopen(marker, "w");
        if (stream != NULL)
            fclose(stream);
    }
    if (keywords == NULL || values == NULL || expand_dbname != 1 ||
        strcmp(keywords[0], "dbname") != 0 || values[0] == NULL || strstr(values[0], "host=fake") == NULL ||
        strcmp(keywords[1], "connect_timeout") != 0 || strcmp(values[1], "5") != 0 ||
        keywords[2] != NULL || values[2] != NULL)
        return NULL;
    return &connection;
}

int PQstatus(void *handle) {
    const char *failure = getenv("RH_FAKE_PG_CONNECT_FAIL");
    return handle != &connection || (failure != NULL && strcmp(failure, "1") == 0) ? 1 : 0;
}

void *PQexecParams(void *handle, const char *query, int count, const unsigned int *types,
                   const char *const *values, const int *lengths, const int *formats,
                   int result_format) {
    static const char *page_values[11] = {
        "00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000002", "4", "7",
        "scope ' ; SELECT pg_sleep(60); --", "", "{\"page\":8}", "complete",
        "2", "", "2026-01-01T00:01:00Z"
    };
    static const char *page_events_values[14] = {
        "00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000002", "4", "7",
        "scope ' ; SELECT pg_sleep(60); --", "", "{\"page\":8}", "complete",
        "0", "", "[]", "[]", "[]", "2026-01-01T00:01:00Z"
    };
    static const char *page_events_subjects_values[14] = {
        "00000000-0000-0000-0000-000000000003", "00000000-0000-0000-0000-000000000004", "1", "1", "pg-adapter-live-events",
        "", "{\"page\":2}", "complete", "1", "",
        "[{\"source_object_type\":\"issue\",\"source_object_id\":\"issue:live\",\"source_revision\":\"revision-1\",\"event_kind\":\"created\",\"subject_id\":\"00000000-0000-0000-0000-000000000005\",\"actor_account_id\":\"00000000-0000-0000-0000-000000000007\",\"occurred_at\":\"2026-09-21T00:00:30Z\",\"observed_at\":\"2026-09-21T00:00:40Z\",\"time_basis\":\"event\",\"evidence_id\":\"00000000-0000-0000-0000-000000000006\",\"parser_version\":\"fixture/1\",\"payload\":{\"state\":\"open\"}}]",
        "[{\"id\":\"00000000-0000-0000-0000-000000000005\",\"entity_kind\":\"issue\",\"visibility_scope\":\"public\",\"created_at\":\"2026-01-01T00:00:00Z\"}]",
        "[{\"id\":\"00000000-0000-0000-0000-000000000007\",\"source_native_id\":\"alice\",\"account_kind\":\"human\",\"display_name\":\"Alice Example\",\"raw_identity_evidence_id\":null,\"visibility_scope\":\"public\"}]",
        "2026-09-21T00:00:45Z"
    };
    static const char *evidence_values[9] = {
        "00000000-0000-0000-0000-000000000006", "public",
        "fe482b5e524c67728f4f2b4f430cd10d9a25659641f995ae537b282ccd181e0b", "15",
        "text/plain", "fnv1a64:f5e19178d3ff184e", "standard", "captured",
        "2026-01-01T00:00:00Z"
    };
    static const char *heartbeat_values[4] = {
        "00000000-0000-0000-0000-000000000002", "4", "2026-01-01T00:01:00Z", "60"
    };
    static const char *finish_values[6] = {
        "00000000-0000-0000-0000-000000000002", "4", "dead_letter",
        "2026-01-01T00:02:00Z", "retry-exhausted", "malformed"
    };
    static const char *finish_collection_values[10] = {
        "00000000-0000-0000-0000-000000000003", "00000000-0000-0000-0000-000000000008", "1",
        "succeeded", "succeeded", "complete", "{\"issues\":\"observed\"}", "ok", "",
        "2026-01-01T00:06:00Z"
    };
    static const char *claim_values[4] = {
        "worker-a", "2026-01-01T00:01:00Z", "60", ""
    };
    static const char *claim_collection_values[4] = {
        "worker-a", "2026-01-01T00:01:00Z", "60", "00000000-0000-0000-0000-00000000000a"
    };
    static const char *enqueue_values[5] = {
        "00000000-0000-0000-0000-000000000003", "00000000-0000-0000-0000-00000000000a",
        "5", "2026-01-01T00:01:00Z", "2026-01-01T00:00:00Z"
    };
    static const char *begin_run_values[13] = {
        "00000000-0000-0000-0000-000000000001", "github", "https://api.github.com",
        "public", "1", "2026-01-01T00:00:00Z", "00000000-0000-0000-0000-000000000003",
        "issues", "github", "1.0.0", "", "", "2026-01-01T00:00:00Z"
    };
    static const char *ingest_begin_values[13] = {
        "00000000-0000-0000-0000-000000000001", "github", "https://api.github.com",
        "public", "1", "2026-01-01T00:00:00Z", "00000000-0000-0000-0000-000000000020",
        "issues", "github", "1.0.0", "", "", "2026-09-21T00:00:00Z"
    };
    static const char *ingest_enqueue_values[5] = {
        "00000000-0000-0000-0000-000000000020", "00000000-0000-0000-0000-000000000021",
        "5", "2026-09-21T00:01:00Z", "2026-09-21T00:00:00Z"
    };
    static const char *ingest_claim_values[4] = {
        "integration-worker", "2026-09-21T00:02:00Z", "120", "00000000-0000-0000-0000-000000000021"
    };
    static const char *ingest_page_values[14] = {
        "00000000-0000-0000-0000-000000000020", "00000000-0000-0000-0000-000000000021", "1", "0",
        "postgres-ingest-live", "", "{\"page\":1}", "complete", "1", "00000000-0000-0000-0000-000000000006",
        "[{\"source_object_type\":\"issue\",\"source_object_id\":\"issue:postgres-ingest-live\",\"source_revision\":\"revision-1\",\"event_kind\":\"created\",\"subject_id\":\"00000000-0000-0000-0000-000000000005\",\"actor_account_id\":\"00000000-0000-0000-0000-000000000007\",\"occurred_at\":\"2026-09-21T00:02:30Z\",\"observed_at\":\"2026-09-21T00:02:35Z\",\"time_basis\":\"event\",\"evidence_id\":\"00000000-0000-0000-0000-000000000006\",\"parser_version\":\"fixture/1\",\"payload\":{\"state\":\"open\"}}]",
        "[{\"id\":\"00000000-0000-0000-0000-000000000005\",\"entity_kind\":\"issue\",\"visibility_scope\":\"public\",\"created_at\":\"2026-01-01T00:00:00Z\"}]",
        "[{\"id\":\"00000000-0000-0000-0000-000000000007\",\"source_native_id\":\"alice\",\"account_kind\":\"human\",\"display_name\":\"Alice Example\",\"raw_identity_evidence_id\":null,\"visibility_scope\":\"public\"}]",
        "2026-09-21T00:03:00Z"
    };
    static const char *ingest_finish_values[10] = {
        "00000000-0000-0000-0000-000000000020", "00000000-0000-0000-0000-000000000021", "1",
        "succeeded", "succeeded", "complete", "{\"issues\":\"observed\"}", "ok", "", "2026-09-21T00:03:30Z"
    };
    static const char *ingest_partial_finish_values[10] = {
        "00000000-0000-0000-0000-000000000020", "00000000-0000-0000-0000-000000000021", "1",
        "succeeded", "partial", "partial", "{\"issues\":\"partial\",\"reason\":\"rate_limit\"}", "partial", "rate_limit", "2026-09-21T00:03:30Z"
    };
    static const char *ingest_failed_finish_values[10] = {
        "00000000-0000-0000-0000-000000000020", "00000000-0000-0000-0000-000000000021", "1",
        "failed", "failed", "unknown", "{\"issues\":\"unavailable\",\"reason\":\"authorization\"}", "authorization", "authorization", "2026-09-21T00:03:30Z"
    };
    static const char *ingest_canceled_finish_values[10] = {
        "00000000-0000-0000-0000-000000000020", "00000000-0000-0000-0000-000000000021", "1",
        "canceled", "canceled", "unknown", "{\"issues\":\"partial\",\"reason\":\"canceled\"}", "canceled", "canceled", "2026-09-21T00:03:30Z"
    };
    const char *operation = getenv("RH_FAKE_PG_OPERATION");
    const char *mode = getenv("RH_FAKE_PG_EXPECT");
    const char **expected = page_values;
    const char *prefix = "SELECT public.rh_commit_collection_page(";
    int expected_count = 11;
    int claim_query = 0;
    if (operation != NULL && strcmp(operation, "begin_run") == 0) {
        expected = begin_run_values;
        expected_count = 13;
        prefix = "SELECT public.rh_begin_collection_run(";
    } else if (operation != NULL && strcmp(operation, "heartbeat") == 0) {
        expected = heartbeat_values;
        expected_count = 4;
        prefix = "SELECT public.rh_heartbeat_job(";
    } else if (operation != NULL && strcmp(operation, "finish") == 0) {
        expected = finish_values;
        expected_count = 6;
        prefix = "SELECT public.rh_finish_job(";
    } else if (operation != NULL && strcmp(operation, "finish_collection") == 0) {
        expected = finish_collection_values;
        expected_count = 10;
        prefix = "SELECT public.rh_finish_collection_job(";
    } else if (operation != NULL && strcmp(operation, "claim") == 0) {
        expected = claim_values;
        expected_count = 4;
        prefix = "SELECT job_id::text, fencing_token::text, lease_expires_at::text FROM public.rh_claim_next_job(";
    } else if (operation != NULL && strcmp(operation, "claim_collection") == 0) {
        expected = claim_collection_values;
        expected_count = 4;
        prefix = "SELECT job_id::text, fencing_token::text, lease_expires_at::text FROM public.rh_claim_next_job(";
    } else if (operation != NULL && strcmp(operation, "enqueue") == 0) {
        expected = enqueue_values;
        expected_count = 5;
        prefix = "SELECT public.rh_enqueue_collection_job(";
    } else if (operation != NULL && strcmp(operation, "page_events") == 0) {
        expected = page_events_values;
        expected_count = 14;
        prefix = "SELECT public.rh_commit_collection_page_events(";
    } else if (operation != NULL && strcmp(operation, "page_events_subjects") == 0) {
        expected = page_events_subjects_values;
        expected_count = 14;
        prefix = "SELECT public.rh_commit_collection_page_events(";
    } else if (operation != NULL && strcmp(operation, "evidence") == 0) {
        expected = evidence_values;
        expected_count = 9;
        prefix = "SELECT public.rh_register_evidence_object(";
    } else if (operation != NULL && strcmp(operation, "ingest") == 0) {
        if (query != NULL && strncmp(query, "SELECT public.rh_register_evidence_object(", strlen("SELECT public.rh_register_evidence_object(")) == 0) {
            expected = evidence_values;
            expected_count = 9;
            prefix = "SELECT public.rh_register_evidence_object(";
        } else if (query != NULL && strncmp(query, "SELECT public.rh_begin_collection_run(", strlen("SELECT public.rh_begin_collection_run(")) == 0) {
            expected = ingest_begin_values;
            expected_count = 13;
            prefix = "SELECT public.rh_begin_collection_run(";
        } else if (query != NULL && strncmp(query, "SELECT public.rh_enqueue_collection_job(", strlen("SELECT public.rh_enqueue_collection_job(")) == 0) {
            expected = ingest_enqueue_values;
            expected_count = 5;
            prefix = "SELECT public.rh_enqueue_collection_job(";
        } else if (query != NULL && strncmp(query, "SELECT job_id::text, fencing_token::text, lease_expires_at::text FROM public.rh_claim_next_job(", strlen("SELECT job_id::text, fencing_token::text, lease_expires_at::text FROM public.rh_claim_next_job(")) == 0) {
            expected = ingest_claim_values;
            expected_count = 4;
            prefix = "SELECT job_id::text, fencing_token::text, lease_expires_at::text FROM public.rh_claim_next_job(";
            claim_query = 1;
        } else if (query != NULL && strncmp(query, "SELECT public.rh_commit_collection_page_events(", strlen("SELECT public.rh_commit_collection_page_events(")) == 0) {
            expected = ingest_page_values;
            expected_count = 14;
            prefix = "SELECT public.rh_commit_collection_page_events(";
        } else if (query != NULL && strncmp(query, "SELECT public.rh_finish_collection_job(", strlen("SELECT public.rh_finish_collection_job(")) == 0) {
            expected = mode != NULL && strcmp(mode, "partial") == 0 ? ingest_partial_finish_values :
                mode != NULL && strcmp(mode, "failed") == 0 ? ingest_failed_finish_values :
                mode != NULL && strcmp(mode, "canceled") == 0 ? ingest_canceled_finish_values : ingest_finish_values;
            expected_count = 10;
            prefix = "SELECT public.rh_finish_collection_job(";
        }
    }
    if (handle != &connection || query == NULL || strncmp(query, prefix, strlen(prefix)) != 0 ||
        count != expected_count || types != NULL || values == NULL || lengths != NULL || formats != NULL || result_format != 0) {
        if (operation != NULL && strcmp(operation, "ingest") == 0)
            fprintf(stderr, "fake libpq ingest call mismatch: query=%s count=%d expected=%d prefix=%s\n", query == NULL ? "(null)" : query, count, expected_count, prefix);
        return NULL;
    }
    for (int i = 0; i < count; ++i)
        if (values[i] == NULL || strcmp(values[i], expected[i]) != 0) {
            if (operation != NULL && strcmp(operation, "ingest") == 0)
                fprintf(stderr, "fake libpq ingest parameter %d mismatch: got=%s expected=%s\n", i, values[i] == NULL ? "(null)" : values[i], expected[i]);
            return NULL;
        }
    if (claim_query || (operation != NULL && (strcmp(operation, "claim") == 0 || strcmp(operation, "claim_collection") == 0))) {
        result.columns = 3;
        result.rows = mode != NULL && strcmp(mode, "duplicate") == 0 ? 0 : 1;
        result.status = mode != NULL && strcmp(mode, "failure") == 0 ? 7 : 2;
        return &result;
    }
    result.columns = 1;
    result.rows = 1;
    if (mode != NULL && strcmp(mode, "duplicate") == 0)
        result.value = "f";
    else
        result.value = "t";
    if (mode != NULL && strcmp(mode, "failure") == 0)
        result.status = 7;
    else
        result.status = 2;
    return &result;
}

void *PQexec(void *handle, const char *query) {
    const char *operation = getenv("RH_FAKE_PG_OPERATION");
    const char *mode = getenv("RH_FAKE_PG_EXPECT");
    if (handle != &connection || operation == NULL || strcmp(operation, "evidence_references") != 0 ||
        query == NULL || strncmp(query, "SELECT json_build_object('storage_keys'", 39) != 0 ||
        strstr(query, "FROM public.evidence_object") == NULL || strstr(query, "LIMIT 100001") == NULL)
        return NULL;
    result.status = mode != NULL && strcmp(mode, "failure") == 0 ? 7 : 2;
    result.rows = 1;
    result.columns = 1;
    result.value = mode != NULL && strcmp(mode, "invalid_refs") == 0 ? evidence_references_invalid_json :
        mode != NULL && strcmp(mode, "truncated_refs") == 0 ? evidence_references_truncated_json :
        mode != NULL && strcmp(mode, "unsorted_refs") == 0 ? evidence_references_unsorted_json : evidence_references_json;
    return &result;
}

int PQresultStatus(void *handle) { return handle == &result ? result.status : 7; }
int PQntuples(void *handle) { return handle == &result ? result.rows : 0; }
int PQnfields(void *handle) { return handle == &result ? result.columns : 0; }
int PQgetisnull(void *handle, int row, int column) {
    return handle != &result || row != 0 || column < 0 || column >= result.columns;
}
char *PQgetvalue(void *handle, int row, int column) {
    if (handle != &result || row != 0 || column < 0 || column >= result.columns)
        return "";
    if (result.columns == 3) {
        const char *operation = getenv("RH_FAKE_PG_OPERATION");
        const char **cells = operation != NULL && strcmp(operation, "ingest") == 0 ? ingest_claim_cells :
            operation != NULL && strcmp(operation, "claim_collection") == 0 ? claim_collection_cells : claim_cells;
        return (char *)cells[column];
    }
    return (char *)result.value;
}
int PQgetlength(void *handle, int row, int column) {
    const char *operation = getenv("RH_FAKE_PG_OPERATION");
    const char *mode = getenv("RH_FAKE_PG_EXPECT");
    if (handle == &result && operation != NULL && strcmp(operation, "evidence_references") == 0 &&
        mode != NULL && strcmp(mode, "oversize") == 0)
        return 4194305;
    return (int)strlen(PQgetvalue(handle, row, column));
}
void PQclear(void *handle) { (void)handle; }
void PQfinish(void *handle) { (void)handle; }
