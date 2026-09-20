#include <stdlib.h>
#include <string.h>

typedef struct { int marker; } FakeConnection;
typedef struct { int status; int rows; int columns; const char *value; } FakeResult;

static FakeConnection connection = { 1 };
static FakeResult result = { 2, 1, 1, "t" };
static const char *claim_cells[3] = {
    "00000000-0000-0000-0000-000000000004", "5", "2026-01-01 00:02:00+00"
};

void *PQconnectdbParams(const char *const *keywords, const char *const *values, int expand_dbname) {
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
    static const char *page_values[9] = {
        "00000000-0000-0000-0000-000000000001", "7",
        "scope ' ; SELECT pg_sleep(60); --", "", "{\"page\":8}", "complete",
        "2", "", "2026-01-01T00:01:00Z"
    };
    static const char *heartbeat_values[4] = {
        "00000000-0000-0000-0000-000000000002", "4", "2026-01-01T00:01:00Z", "60"
    };
    static const char *finish_values[6] = {
        "00000000-0000-0000-0000-000000000002", "4", "dead_letter",
        "2026-01-01T00:02:00Z", "retry-exhausted", "malformed"
    };
    static const char *claim_values[3] = {
        "worker-a", "2026-01-01T00:01:00Z", "60"
    };
    const char *operation = getenv("RH_FAKE_PG_OPERATION");
    const char **expected = page_values;
    const char *prefix = "SELECT public.rh_commit_collection_page(";
    int expected_count = 9;
    if (operation != NULL && strcmp(operation, "heartbeat") == 0) {
        expected = heartbeat_values;
        expected_count = 4;
        prefix = "SELECT public.rh_heartbeat_job(";
    } else if (operation != NULL && strcmp(operation, "finish") == 0) {
        expected = finish_values;
        expected_count = 6;
        prefix = "SELECT public.rh_finish_job(";
    } else if (operation != NULL && strcmp(operation, "claim") == 0) {
        expected = claim_values;
        expected_count = 3;
        prefix = "SELECT job_id::text, fencing_token::text, lease_expires_at::text FROM public.rh_claim_next_job(";
    }
    if (handle != &connection || query == NULL || strncmp(query, prefix, strlen(prefix)) != 0 ||
        count != expected_count || types != NULL || values == NULL || lengths != NULL || formats != NULL || result_format != 0)
        return NULL;
    for (int i = 0; i < count; ++i)
        if (values[i] == NULL || strcmp(values[i], expected[i]) != 0)
            return NULL;
    const char *mode = getenv("RH_FAKE_PG_EXPECT");
    if (operation != NULL && strcmp(operation, "claim") == 0) {
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

int PQresultStatus(void *handle) { return handle == &result ? result.status : 7; }
int PQntuples(void *handle) { return handle == &result ? result.rows : 0; }
int PQnfields(void *handle) { return handle == &result ? result.columns : 0; }
int PQgetisnull(void *handle, int row, int column) {
    return handle != &result || row != 0 || column < 0 || column >= result.columns;
}
char *PQgetvalue(void *handle, int row, int column) {
    if (handle != &result || row != 0 || column < 0 || column >= result.columns)
        return "";
    return result.columns == 3 ? (char *)claim_cells[column] : (char *)result.value;
}
int PQgetlength(void *handle, int row, int column) {
    return (int)strlen(PQgetvalue(handle, row, column));
}
void PQclear(void *handle) { (void)handle; }
void PQfinish(void *handle) { (void)handle; }
