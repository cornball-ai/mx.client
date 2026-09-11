# The version describes mx.client's file envelope, not the encrypted
# vodozemac payload. Only sessions.json had an unversioned JSON format.
crypto_store_version <- function(blob, path, legacy = FALSE) {
    if (is.list(blob) && legacy && !"version" %in% names(blob)) {
        return(invisible(0L))
    }
    version <- if (is.list(blob)) blob[["version"]] else NULL
    if (!is.list(blob) || sum(names(blob) == "version") != 1L ||
        !(identical(version, 1L) || identical(version, 1))) {
        stop("mx.client: unsupported or invalid schema version in ",
            path, "; expected version 1. No store was replaced.",
            call. = FALSE)
    }
    invisible(1L)
}

# Read raw account pickles and versioned envelopes without rewriting them.
# Account saves stay raw until older clients no longer need to read the store.
crypto_account_pickle <- function(path) {
    pickle <- trimws(paste(readLines(path, warn = FALSE), collapse = ""))
    if (startsWith(pickle, "{")) {
        blob <- jsonlite::fromJSON(pickle, simplifyVector = FALSE)
        crypto_store_version(blob, path)
        pickle <- blob[["pickle"]]
    }
    if (!is.character(pickle) || length(pickle) != 1L ||
        is.na(pickle) || !nzchar(pickle)) {
        stop("mx.client: invalid ", path, "; expected an encrypted pickle. ",
            "No identity was replaced.", call. = FALSE)
    }
    pickle
}
