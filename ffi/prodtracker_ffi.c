/*
 * prodtracker_ffi.c — C shims for ProdTracker.
 *
 * Provides PostgreSQL connection management and the bridge between
 * ConnectionHandle and USize for the SWELib FFI layer.
 */

#include <lean/lean.h>
#include <libpq-fe.h>
#include <stdlib.h>
#include <string.h>

/* ── External object class for PGconn ─────────────────────────── */

static void pgconn_finalize(void *ptr) {
    if (ptr) PQfinish((PGconn *)ptr);
}

static void pgconn_foreach(void *ptr, b_lean_obj_arg f) {
    (void)ptr; (void)f;
}

static lean_external_class *g_pgconn_class = NULL;

static lean_external_class *get_pgconn_class(void) {
    if (!g_pgconn_class) {
        g_pgconn_class = lean_register_external_class(pgconn_finalize, pgconn_foreach);
    }
    return g_pgconn_class;
}

/* ── Helper: Lean Option String ───────────────────────────────── */

static const char *option_string_val(b_lean_obj_arg opt) {
    if (lean_obj_tag(opt) == 0) return NULL;  /* none */
    return lean_string_cstr(lean_ctor_get(opt, 0));
}

static lean_obj_res mk_option_string(const char *s) {
    if (!s) return lean_box(0);
    lean_object *obj = lean_alloc_ctor(1, 1, 0);
    lean_ctor_set(obj, 0, lean_mk_string(s));
    return obj;
}

/* ── swelib_pq_connect ─────────────────────────────────────────── */
/*
 * ConnectionParameters → IO (Option ConnectionHandle)
 *
 * ConnectionParameters is a structure with fields:
 *   host, port, dbname, user, password, connect_timeout,
 *   sslmode, sslrootcert, sslcert, sslkey, target_session_attrs
 * All are Option String except port and connect_timeout which are Option Nat.
 */
LEAN_EXPORT lean_obj_res swelib_pq_connect(b_lean_obj_arg params, lean_obj_arg world) {
    /* Extract fields from the structure. Field order matches the Lean struct. */
    b_lean_obj_arg host_opt     = lean_ctor_get(params, 0);
    b_lean_obj_arg port_opt     = lean_ctor_get(params, 1);
    b_lean_obj_arg dbname_opt   = lean_ctor_get(params, 2);
    b_lean_obj_arg user_opt     = lean_ctor_get(params, 3);
    b_lean_obj_arg password_opt = lean_ctor_get(params, 4);

    const char *host     = option_string_val(host_opt);
    const char *dbname   = option_string_val(dbname_opt);
    const char *user     = option_string_val(user_opt);
    const char *password = option_string_val(password_opt);

    /* Build connection string */
    char conninfo[1024];
    int off = 0;
    if (host)     off += snprintf(conninfo + off, sizeof(conninfo) - off, "host=%s ", host);
    if (dbname)   off += snprintf(conninfo + off, sizeof(conninfo) - off, "dbname=%s ", dbname);
    if (user)     off += snprintf(conninfo + off, sizeof(conninfo) - off, "user=%s ", user);
    if (password) off += snprintf(conninfo + off, sizeof(conninfo) - off, "password=%s ", password);

    /* Handle port (Option Nat) */
    if (lean_obj_tag(port_opt) == 1) {
        lean_object *nat = lean_ctor_get(port_opt, 0);
        size_t port = lean_unbox(nat);
        off += snprintf(conninfo + off, sizeof(conninfo) - off, "port=%zu ", port);
    }

    if (off == 0) {
        /* No params — use defaults */
        conninfo[0] = '\0';
    }

    PGconn *conn = PQconnectdb(conninfo);
    if (!conn) {
        /* Return none */
        return lean_io_result_mk_ok(lean_box(0));
    }

    if (PQstatus(conn) != CONNECTION_OK) {
        PQfinish(conn);
        return lean_io_result_mk_ok(lean_box(0));
    }

    /* Wrap in external object */
    lean_object *handle = lean_alloc_external(get_pgconn_class(), conn);
    /* Return some handle */
    lean_object *some = lean_alloc_ctor(1, 1, 0);
    lean_ctor_set(some, 0, handle);
    return lean_io_result_mk_ok(some);
}

/* ── swelib_pq_status ──────────────────────────────────────────── */
/*
 * ConnectionHandle → IO ConnectionStatus
 *
 * ConnectionStatus is an inductive with 12 constructors (tags 0..11).
 */
LEAN_EXPORT lean_obj_res swelib_pq_status(b_lean_obj_arg handle, lean_obj_arg world) {
    PGconn *conn = (PGconn *)lean_get_external_data(handle);
    ConnStatusType s = PQstatus(conn);
    unsigned tag;
    switch (s) {
        case CONNECTION_OK:                 tag = 0; break;
        case CONNECTION_BAD:                tag = 1; break;
        case CONNECTION_STARTED:            tag = 2; break;
        case CONNECTION_MADE:               tag = 3; break;
        case CONNECTION_AWAITING_RESPONSE:  tag = 4; break;
        case CONNECTION_AUTH_OK:            tag = 5; break;
        case CONNECTION_SSL_STARTUP:        tag = 6; break;
#ifdef CONNECTION_GSS_STARTUP
        case CONNECTION_GSS_STARTUP:        tag = 7; break;
#endif
        case CONNECTION_CHECK_WRITABLE:     tag = 8; break;
        case CONNECTION_CHECK_STANDBY:      tag = 9; break;
        case CONNECTION_CONSUME:            tag = 10; break;
        case CONNECTION_SETENV:             tag = 11; break;
        default:                            tag = 1; break; /* BAD */
    }
    return lean_io_result_mk_ok(lean_box(tag));
}

/* ── swelib_pq_close ───────────────────────────────────────────── */
/*
 * ConnectionHandle → IO Unit
 *
 * We set the external data to NULL so the finalizer won't double-free.
 */
LEAN_EXPORT lean_obj_res swelib_pq_close(lean_obj_arg handle, lean_obj_arg world) {
    PGconn *conn = (PGconn *)lean_get_external_data(handle);
    if (conn) {
        PQfinish(conn);
        lean_set_external_data(handle, NULL);
    }
    lean_dec_ref(handle);
    return lean_io_result_mk_ok(lean_box(0));
}

/* ── swelib_pq_error_message ───────────────────────────────────── */
/*
 * ConnectionHandle → IO String
 */
LEAN_EXPORT lean_obj_res swelib_pq_error_message(b_lean_obj_arg handle, lean_obj_arg world) {
    PGconn *conn = (PGconn *)lean_get_external_data(handle);
    const char *msg = conn ? PQerrorMessage(conn) : "null connection";
    return lean_io_result_mk_ok(lean_mk_string(msg));
}

/* ── swelib_pq_exec ────────────────────────────────────────────── */
/*
 * ConnectionHandle → String → IO (Option QueryResult)
 *
 * QueryResult is also wrapped as an external object.
 */
static lean_external_class *g_pgresult_class = NULL;

static void pgresult_finalize(void *ptr) {
    if (ptr) PQclear((PGresult *)ptr);
}

static void pgresult_foreach(void *ptr, b_lean_obj_arg f) {
    (void)ptr; (void)f;
}

static lean_external_class *get_pgresult_class(void) {
    if (!g_pgresult_class) {
        g_pgresult_class = lean_register_external_class(pgresult_finalize, pgresult_foreach);
    }
    return g_pgresult_class;
}

LEAN_EXPORT lean_obj_res swelib_pq_exec(b_lean_obj_arg handle, b_lean_obj_arg sql, lean_obj_arg world) {
    PGconn *conn = (PGconn *)lean_get_external_data(handle);
    const char *query = lean_string_cstr(sql);

    PGresult *result = PQexec(conn, query);
    if (!result) {
        return lean_io_result_mk_ok(lean_box(0)); /* none */
    }

    ExecStatusType s = PQresultStatus(result);
    if (s == PGRES_COMMAND_OK || s == PGRES_TUPLES_OK) {
        lean_object *ext = lean_alloc_external(get_pgresult_class(), result);
        lean_object *some = lean_alloc_ctor(1, 1, 0);
        lean_ctor_set(some, 0, ext);
        return lean_io_result_mk_ok(some);
    }

    PQclear(result);
    return lean_io_result_mk_ok(lean_box(0)); /* none on error */
}

/* ── swelib_conn_handle_to_usize ───────────────────────────────── */
/*
 * ConnectionHandle → USize
 * Extract the raw PGconn* pointer for use with the FFI layer.
 */
LEAN_EXPORT size_t swelib_conn_handle_to_usize(b_lean_obj_arg handle) {
    return (size_t)lean_get_external_data(handle);
}

/* ── swelib_pq_validate ────────────────────────────────────────── */
LEAN_EXPORT lean_obj_res swelib_pq_validate(b_lean_obj_arg handle, lean_obj_arg world) {
    PGconn *conn = (PGconn *)lean_get_external_data(handle);
    PGresult *res = PQexec(conn, "SELECT 1");
    if (!res) return lean_io_result_mk_ok(lean_box(0));
    int ok = (PQresultStatus(res) == PGRES_TUPLES_OK);
    PQclear(res);
    return lean_io_result_mk_ok(lean_box(ok ? 1 : 0));
}

/* ── swelib_pq_reset ───────────────────────────────────────────── */
LEAN_EXPORT lean_obj_res swelib_pq_reset(lean_obj_arg handle, lean_obj_arg world) {
    PGconn *conn = (PGconn *)lean_get_external_data(handle);
    PQreset(conn);
    int ok = (PQstatus(conn) == CONNECTION_OK);
    return lean_io_result_mk_ok(lean_box(ok ? 1 : 0));
}

/* ── swelib_pq_ping ────────────────────────────────────────────── */
LEAN_EXPORT lean_obj_res swelib_pq_ping(b_lean_obj_arg handle, lean_obj_arg world) {
    PGconn *conn = (PGconn *)lean_get_external_data(handle);
    PGresult *res = PQexec(conn, "SELECT 1");
    if (!res) return lean_io_result_mk_ok(lean_box(0));
    int ok = (PQresultStatus(res) == PGRES_TUPLES_OK);
    PQclear(res);
    return lean_io_result_mk_ok(lean_box(ok ? 1 : 0));
}

/* ── swelib_pq_is_writable / swelib_pq_is_readable ─────────────── */
LEAN_EXPORT lean_obj_res swelib_pq_is_writable(b_lean_obj_arg handle, lean_obj_arg world) {
    PGconn *conn = (PGconn *)lean_get_external_data(handle);
    return lean_io_result_mk_ok(lean_box(PQstatus(conn) == CONNECTION_OK ? 1 : 0));
}

LEAN_EXPORT lean_obj_res swelib_pq_is_readable(b_lean_obj_arg handle, lean_obj_arg world) {
    PGconn *conn = (PGconn *)lean_get_external_data(handle);
    return lean_io_result_mk_ok(lean_box(PQstatus(conn) == CONNECTION_OK ? 1 : 0));
}
