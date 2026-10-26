library(mx.client)
if (!requireNamespace("mx.crypto", quietly = TRUE) ||
    !"mxc_attachment_encrypt" %in% getNamespaceExports("mx.crypto")) {
    exit_file("encrypted attachments require mx.crypto >= 0.2.2.2")
}
local({
    root <- tempfile("media-test-")
    dir.create(root)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    path <- file.path(root, "fixture.png")
    bytes <- as.raw(0:255)
    writeBin(bytes, path)
    cfg <- list(server = "https://example.invalid", token = "fixture-token",
                user_id = "@bot:example.invalid", device_id = "FIXTURE")
    old_upload <- mx.api::mx_upload
    old_download <- mx.api::mx_download
    old_state <- mx.api::mx_get_state
    old_media <- mx.api::mx_send_media
    on.exit({
        assignInNamespace("mx_upload", old_upload, "mx.api")
        assignInNamespace("mx_download", old_download, "mx.api")
        assignInNamespace("mx_get_state", old_state, "mx.api")
        assignInNamespace("mx_send_media", old_media, "mx.api")
    }, add = TRUE)
    uploaded <- NULL
    assignInNamespace("mx_upload", function(session, path, content_type, filename) {
        expect_identical(session$token, "fixture-token")
        expect_identical(content_type, "application/octet-stream")
        expect_identical(filename, "encrypted")
        uploaded <<- readBin(path, "raw", file.size(path))
        "mxc://example.invalid/fixture"
    }, "mx.api")
    content <- mx_upload_encrypted(cfg, path)
    expect_identical(content$msgtype, "m.image")
    expect_identical(content$body, "fixture.png")
    expect_identical(content$info$mimetype, "image/png")
    expect_equal(content$info$size, 256)
    expect_null(content$url)
    expect_false(identical(uploaded, bytes))
    expect_identical(mx.crypto::mxc_attachment_decrypt(uploaded, content$file), bytes)
    expect_error(mx_upload_encrypted(cfg, path, max_bytes = 255), "size limit")
    expect_error(mx_upload_encrypted(cfg, root), "readable file")
    expect_error(mx_upload_encrypted(cfg, path, max_bytes = Inf), "size limit")
    assignInNamespace("mx_download", function(session, mxc_url, dest) {
        expect_identical(session$token, "fixture-token")
        expect_identical(mxc_url, content$file$url)
        writeBin(uploaded, dest)
        invisible(dest)
    }, "mx.api")
    dest <- file.path(root, "received.png")
    expect_identical(mx_download_encrypted(cfg, content$file, dest), dest)
    expect_identical(readBin(dest, "raw", 256), bytes)
    # A failed integrity/size check leaves the existing destination intact.
    uploaded[1] <- as.raw(bitwXor(as.integer(uploaded[1]), 1L))
    expect_error(mx_download_encrypted(cfg, content$file, dest), "integrity")
    expect_identical(readBin(dest, "raw", 256), bytes)
    expect_error(mx_download_encrypted(cfg, content$file, dest, max_bytes = 255), "size limit")
    expect_identical(readBin(dest, "raw", 256), bytes)
    expect_error(mx_download_encrypted(cfg, list(url = "https://example.invalid"), dest), "media URI")
    # The old convenience sender must never upload plaintext to an encrypted
    # room, including when state cannot be determined.
    sends <- 0L
    assignInNamespace("mx_send_media", function(...) { sends <<- sends + 1L; "$plain" }, "mx.api")
    assignInNamespace("mx_get_state", function(...) list(algorithm = "m.megolm.v1.aes-sha2"), "mx.api")
    expect_error(mx_send_media(cfg, path, "!room:example.invalid"), "encrypted room")
    expect_identical(sends, 0L)
    assignInNamespace("mx_get_state", function(...) stop("state unavailable"), "mx.api")
    expect_error(mx_send_media(cfg, path, "!room:example.invalid"), "state unavailable")
    expect_identical(sends, 0L)
    assignInNamespace("mx_get_state", function(...) NULL, "mx.api")
    expect_identical(mx_send_media(cfg, path, "!room:example.invalid"), "$plain")
    expect_identical(sends, 1L)
})
