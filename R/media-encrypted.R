#' Upload an encrypted Matrix attachment
#'
#' Uploads ciphertext only, with a generic filename and content type.
#' Returns content to pass to \code{mx_send_encrypted()} using the caller's
#' existing account and sessions. The return value includes a secret key:
#' never post it in an unencrypted event. Does not open a crypto store.
#' @param client Matrix client config.
#' @param path Path of the file to upload.
#' @param body Display filename or caption, inside the encrypted event.
#' @param msgtype Media message type, or NULL to derive it from the MIME type.
#' @param content_type MIME type, or NULL to guess from the file extension.
#' @param info Extra media metadata, inside the encrypted event.
#' @param max_bytes Maximum plaintext size in bytes, default 25 MiB. Encryption
#'   uses memory; larger files require an explicit higher limit.
#' @return Matrix message content with \code{file} instead of \code{url}.
#' @export
mx_upload_encrypted <- function(client, path, body = basename(path),
                                msgtype = NULL, content_type = NULL,
                                info = list(), max_bytes = 25 * 1024^2) {
    mx_require_attachment_crypto()
    size <- mx_attachment_size(path, max_bytes)
    content_type <- content_type %||% mx.api::mx_guess_mime(path)
    if (is.null(msgtype)) {
        family <- sub("/.*", "", content_type)
        msgtype <- if (family %in% c("image", "audio", "video")) {
            paste0("m.", family)
        } else "m.file"
    }
    if (!msgtype %in% c("m.file", "m.image", "m.audio", "m.video")) {
        stop("mx.client: invalid media message type", call. = FALSE)
    }
    # Read one extra byte to catch growth between stat and read.
    bytes <- readBin(path, "raw", n = size + 1)
    if (length(bytes) != size) {
        stop("mx.client: attachment changed while reading", call. = FALSE)
    }
    encrypted <- mx.crypto::mxc_attachment_encrypt(bytes)
    tmp <- tempfile("mx-attachment-")
    dir.create(tmp, mode = "0700")
    on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
    payload <- file.path(tmp, "encrypted")
    writeBin(encrypted$data, payload)
    uri <- mx.api::mx_upload(mx_client_session(client), payload,
                             content_type = "application/octet-stream",
                             filename = "encrypted")
    if (!is.character(uri) || length(uri) != 1L || is.na(uri) ||
        !grepl("^mxc://[^/]+/.+", uri)) {
        stop("mx.client: upload returned no media URI", call. = FALSE)
    }
    encrypted$file$url <- uri
    list(msgtype = msgtype, body = body, file = encrypted$file,
         info = utils::modifyList(info, list(mimetype = content_type, size = size)))
}

#' Download and verify an encrypted Matrix attachment
#'
#' Downloads ciphertext into a private temporary directory, verifies its
#' SHA-256 digest and decrypts it before replacing the destination. Failure
#' leaves an existing destination unchanged. Metadata must come from an
#' authenticated encrypted room event. Does not open a crypto store.
#' @param client Matrix client config.
#' @param file Matrix v2 encrypted-file metadata, including its \code{url}.
#' @param dest Destination path. Its parent directory must exist.
#' @param max_bytes Maximum downloaded size to read into memory, default 25
#'   MiB. This is checked on disk before decryption, not a network transfer cap.
#' @return Destination path, invisibly.
#' @export
mx_download_encrypted <- function(client, file, dest,
                                  max_bytes = 25 * 1024^2) {
    mx_require_attachment_crypto()
    if (!is.list(file) || !is.character(file$url) || length(file$url) != 1L ||
        is.na(file$url) || !grepl("^mxc://[^/]+/.+", file$url)) {
        stop("mx.client: encrypted attachment has no media URI", call. = FALSE)
    }
    tmp <- tempfile("mx-attachment-")
    dir.create(tmp, mode = "0700")
    on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
    payload <- file.path(tmp, "encrypted")
    mx.api::mx_download(mx_client_session(client), file$url, payload)
    size <- mx_attachment_size(payload, max_bytes)
    bytes <- readBin(payload, "raw", n = size)
    plaintext <- mx.crypto::mxc_attachment_decrypt(bytes, file)
    staged <- tempfile(".mx-attachment-", tmpdir = dirname(dest))
    on.exit(unlink(staged), add = TRUE)
    # Create private before writing plaintext, including with a permissive umask.
    if (!file.create(staged) || !Sys.chmod(staged, "0600")) {
        stop("mx.client: cannot create private attachment destination", call. = FALSE)
    }
    writeBin(plaintext, staged)
    if (!file.rename(staged, dest)) {
        stop("mx.client: cannot replace attachment destination", call. = FALSE)
    }
    invisible(dest)
}

mx_require_attachment_crypto <- function() {
    if (!requireNamespace("mx.crypto", quietly = TRUE) ||
        !all(c("mxc_attachment_encrypt", "mxc_attachment_decrypt") %in%
             getNamespaceExports("mx.crypto"))) {
        stop("mx.client: encrypted attachments require mx.crypto >= 0.2.2.2",
             call. = FALSE)
    }
}

mx_attachment_size <- function(path, max_bytes) {
    if (!is.numeric(max_bytes) || length(max_bytes) != 1L ||
        is.na(max_bytes) || !is.finite(max_bytes) || max_bytes < 0 ||
        max_bytes > .Machine$integer.max - 1) {
        stop("mx.client: invalid attachment size limit", call. = FALSE)
    }
    stat <- file.info(path)
    if (nrow(stat) != 1L || is.na(stat$size) || isTRUE(stat$isdir)) {
        stop("mx.client: attachment must be a readable file", call. = FALSE)
    }
    if (stat$size > max_bytes) {
        stop("mx.client: attachment exceeds the size limit", call. = FALSE)
    }
    stat$size
}
