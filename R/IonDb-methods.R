#' @include IonDb.R

#' @importFrom methods show
#'
#' @export
setMethod("show", "IonDb", function(object) {
    callNextMethod()
    con <- .dbconn(object)
    if (!is.null(con)) {
        if (length(.dbname(object)))
            on.exit(dbDisconnect(con))
        ion_nr <- dbGetQuery(con, paste0("select count(distinct ion_id) ",
                                         "from ms_ion"))
        cat(" ion count:", ion_nr[1, 1], "\n")
    }
})

#' @export
#'
#' @rdname IonDb
setMethod("ionVariables", "IonDb", function(object, includeId = FALSE, ...) {
    if (length(.tables(object))) {
        cn <- .tables(object)$ms_ion
        if (includeId)
            cn
        else cn[!cn %in% "ion_id"]
    } else character()
})

#' @importFrom tibble as_tibble
#'
#' @importMethodsFrom ProtGenerics ions
#'
#' @export
#'
#' @rdname IonDb
setMethod("ions", "IonDb", function(object,
                                    columns = ionVariables(object),
                                    filter,
                                    return.type = c("data.frame",
                                                    "tibble"), ...) {
    return.type <- match.arg(return.type)
    if (length(columns))
        res <- .fetch_data(object, columns = columns, filter = filter,
                           start_from = "ms_ion")
    else res <- data.frame()
    if (return.type == "tibble")
        as_tibble(res)
    else res
})

#' @importFrom DBI dbAppendTable dbGetQuery
#'
#' @export
#'
#' @rdname IonDb
setMethod("insertIon", "IonDb", function(object, ions, addColumns = FALSE) {
    if (is.data.frame(ions))
        ions$compound_id <- as.character(ions$compound_id)
    .valid_ion(ions, error = TRUE)
    dbcon <- .dbconn(object)
    if (length(.dbname(object)) && !is.null(dbcon))
        on.exit(dbDisconnect(dbcon))
    if (!is.null(dbcon) && nrow(ions)) {
        if (!all(ions$compound_id %in%
                 dbGetQuery(dbcon, "select compound_id from ms_compound")[, 1]))
            stop("All values of 'compound_id' column of 'ions' must be",
                 " in 'compound_id' column of the 'ms_compound' table of",
                 " 'object'. List all avaliable compound IDs with ",
                 "'compounds(object, c(\"name\", \"compound_id\")'")
        if (any(colnames(ions) == "ion_id"))
            warning("Column 'ion_id' will be replaced with internal ",
                    "identifiers.")
        max_id <- 0
        tmp <- dbGetQuery(dbcon, "select max(ion_id) from ms_ion")
        if (!is.na(tmp[1, 1]))
            max_id <- as.integer(tmp[1, 1])
        ions$ion_id <- max_id + seq_len(nrow(ions))
        cols <- colnames(dbGetQuery(dbcon, "select * from ms_ion limit 1"))
        new_cols <- colnames(ions)[!colnames(ions) %in% cols]
        if (addColumns && length(new_cols)) {
            dtype <- dbDataType(dbcon, ions[, new_cols, drop = FALSE])
            dtype <- paste(names(dtype), dtype)
            for (dt in dtype)
                dbExecute(dbcon, paste("alter table ms_ion add", dt))
            cols <- colnames(dbGetQuery(dbcon, "select * from ms_ion limit 1"))
            object@.properties$tables$ms_ion <- cols
        }
        dbAppendTable(dbcon, "ms_ion", ions)
        invisible(object)
    } else stop("Database not initialized")
    object
})

#' @importFrom DBI dbGetQuery dbExecute
#'
#' @export
#'
#' @rdname IonDb
setMethod("deleteIon", signature(object = "IonDb"),
          function(object, ids = integer(0), ...) {
              dbcon <- .dbconn(object)
              if (is.null(dbcon))
                  stop("Database not initialized")
              if (length(.dbname(object)))
                  on.exit(dbDisconnect(dbcon))
              # maybe this check can be removed?
              if (any(!ids %in% dbGetQuery(dbcon,
                                           paste0("select ion_id ",
                                                  "from ms_ion"))[, 1]))
                  warning("Some IDs in 'ids' are not valid and will be ignored")
              dbExecute(dbcon, paste0("delete from ms_ion where ion_id in (",
                                      toString(ids), ")"))
              object
          })


#' @rdname IonDb
#'
#' @exportMethod IonDb
#'
#' @importFrom RSQLite SQLITE_RWC
setMethod("IonDb", signature(x = "missing", cdb = "missing"),
          function(x, cdb, flags = SQLITE_RWC, ...) {
              .IonDb()
          })

## for character or CompDb with @dbname: only store @dbname but no connection.

#' @rdname IonDb
setMethod("IonDb", signature(x = "CompDb", cdb = "missing"),
          function(x, cdb, ions = data.frame(), ...) {
              con <- .dbconn(x)
              .create_ion_table(con)
              IonDb(con, ions = ions, .DBNAME = .dbname(x),
                    flags = .dbflags(x), ...)
          })

#' @rdname IonDb
setMethod("IonDb", signature(x = "character", cdb = "missing"),
          function(x, cdb, flags = SQLITE_RW, ...) {
              con <- dbConnect(dbDriver("SQLite"), x)
              IonDb(con, ..., .DBNAME = x, flags = flags)
          })

#' @rdname IonDb
setMethod("IonDb", signature(x = "DBIConnection", cdb = "missing"),
          function(x, cdb, ions = data.frame(), flags = SQLITE_RW, ...,
                   .DBNAME = character()) {
              res <- .validCompDb(x)
              if (is.character(res)) stop(res)
              res <- .validIonDb(x)
              if (is.character(res)) stop(res)
              if (length(.DBNAME)) {
                  idb <- .IonDb(dbname = .DBNAME, dbflags = flags)
                  dbDisconnect(x)
              } else idb <- .IonDb(dbcon = x, dbflags = flags)
              idb <- .initialize_compdb(idb)
              if (nrow(ions))
                  insertIon(idb, ions)
              idb
          })

#' @rdname IonDb
setMethod("IonDb", signature(x = "character", cdb = "CompDb"),
          function(x, cdb, ions = data.frame(), flags = SQLITE_RW, ...) {
              con <- dbConnect(dbDriver("SQLite"), x)
              IonDb(con, cdb = cdb, ions = ions, flags = flags,
                    ..., .DBNAME = x)
          })

#' @rdname IonDb
setMethod("IonDb", signature(x = "DBIConnection", cdb = "CompDb"),
          function(x, cdb, ions = data.frame(), flags = SQLITE_RW, ...,
                   .DBNAME = character()) {
              con <- .dbconn(cdb)
              if (length(.dbname(cdb)) && !is.null(con))
                  on.exit(dbDisconnect(con))
              .copy_compdb(con, x)
              .create_ion_table(x)
              IonDb(x, ions = ions, flags = flags, ..., .DBNAME = .DBNAME)
          })

setMethod("deleteCompound", "IonDb", function(object, ids = character(),
                                               recursive = FALSE, ...) {
    dbcon <- .dbconn(object)
    if (is.null(dbcon)) stop("Database not initialized")
    if (length(.dbname(object)))
        on.exit(dbDisconnect(dbcon))
    if (!length(ids)) return(object)
    id_string <- paste0("'", ids, "'", collapse = ",")
    ins <- dbGetQuery(dbcon, paste0("select compound_id, ion_id from ms_ion",
                                    " where compound_id in (", id_string, ");"))
    if (nrow(ins)) {
        if (recursive)
            dbExecute(dbcon, paste0("delete from ms_ion where ion_id in (",
                                    paste0("'", ins$ion_id, "'", collapse =","),
                                    ");"))
        else stop("Ions for ", length(unique(ins$compound_id)), " of the ",
                  "specified compounds present. Use parameter 'recursive = ",
                  "TRUE' to delete compounds and all ions (and eventually MS2",
                  " spectra) associated with them from the database.")
    }
    callNextMethod()
})
