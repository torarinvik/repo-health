#include <stdlib.h>
#include <string.h>

typedef struct { int marker; } FakeConnection;
typedef struct { int status; int rows; int columns; const char *value; } FakeResult;

static FakeConnection connection = { 1 };
static FakeResult result = { 2, 1, 1, "t" };

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
    static const char *expected[9] = {
        "00000000-0000-0000-0000-000000000001", "7",
        "scope ' ; SELECT pg_sleep(60); --", "", "{\"page\":8}", "complete",
        "2", "", "2026-01-01T00:01:00Z"
    };
    if (handle != &connection || query == NULL || strncmp(query, "SELECT public.rh_commit_collection_page(", 40) != 0 ||
        count != 9 || types != NULL || values == NULL || lengths != NULL || formats != NULL || result_format != 0)
        return NULL;
    for (int i = 0; i < count; ++i)
        if (values[i] == NULL || strcmp(values[i], expected[i]) != 0)
            return NULL;
    const char *mode = getenv("RH_FAKE_PG_EXPECT");
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
    return handle != &result || row != 0 || column != 0;
}
char *PQgetvalue(void *handle, int row, int column) {
    return handle == &result && row == 0 && column == 0 ? (char *)result.value : "";
}
void PQclear(void *handle) { (void)handle; }
void PQfinish(void *handle) { (void)handle; }
