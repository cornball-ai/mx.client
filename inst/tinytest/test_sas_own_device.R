library(tinytest)
if (!requireNamespace("mx.crypto", quietly = TRUE) ||
    !"mxc_sas_commitment" %in% getNamespaceExports("mx.crypto")) {
    exit_file("mx.crypto SAS primitives are unavailable")
}
library(mx.client)
local({
    uid <- "@me:example.org"
    store <- tempfile("sas-own-")
    on.exit(unlink(store, recursive = TRUE), add = TRUE)
    signing <- mx.client:::mx_crypto_cross_signing_new()
    a <- mx.crypto::mxc_account_new()
    b <- mx.crypto::mxc_account_new()
    mx.client:::mx_crypto_cross_signing_save(signing, store)
    mx_crypto_account_save(a, store)
    mx_crypto_sessions_save(mx_crypto_sessions_new(), store)
    objects <- mx.client:::mx_crypto_cross_signing_objects(signing, uid, a, "A")
    devices <- list(A = mx_crypto_device_keys(a, uid, "A"),
        B = mx_crypto_device_keys(b, uid, "B"))
    client <- list(server = "https://example.invalid", token = "fixture",
        user_id = uid, device_id = "A")
    original_query <- mx.api::mx_keys_query
    original_upload <- mx.api::mx_keys_signatures_upload
    on.exit({
        assignInNamespace("mx_keys_query", original_query, "mx.api")
        assignInNamespace("mx_keys_signatures_upload", original_upload, "mx.api")
    }, add = TRUE)
    queries <- uploads <- 0L
    assignInNamespace("mx_keys_query", function(...) {
        queries <<- queries + 1L
        list(master_keys = setNames(list(objects$master), uid),
            self_signing_keys = setNames(list(objects$self_signing), uid),
            user_signing_keys = setNames(list(objects$user_signing), uid),
            device_keys = setNames(list(devices), uid))
    }, "mx.api")
    assignInNamespace("mx_keys_signatures_upload", function(session, signatures) {
        uploads <<- uploads + 1L
        expect_identical(names(signatures), uid)
        expect_identical(names(signatures[[uid]]), "B")
        # /keys/signatures/upload merges signatures into the existing device;
        # it does not replace the device object or remove its self-signature.
        incoming <- signatures[[uid]]$B$signatures
        for (signer in names(incoming)) for (key_id in names(incoming[[signer]])) {
            devices$B$signatures[[signer]][[key_id]] <<- incoming[[signer]][[key_id]]
        }
        list()
    }, "mx.api")
    request <- list(type = "m.key.verification.request", sender = uid,
        content = list(from_device = "B", transaction_id = "t",
            timestamp = floor(as.numeric(Sys.time()) * 1000), methods = list("m.sas.v1")))
    sa <- mx_sas_from_request(client, store, request)
    sb <- mx_sas_session(uid, "B", sa$peer_keys, uid, "A", sa$keys, "t", initiator = TRUE)
    transfer <- function(from, to, device_only = FALSE) {
        for (e in mx_sas_outgoing(from)) {
            if (device_only && e$type == "m.key.verification.mac") {
                e$content$mac <- e$content$mac["ed25519:B"]
                # Independent single-device key-list MAC from the Matrix formula.
                e$content$keys <- mx.crypto::mxc_sas_mac(from$crypto, "ed25519:B",
                    paste0("MATRIX_KEY_VERIFICATION_MAC", uid, "B", uid, "A", "tKEY_IDS"))
            }
            mx_sas_receive(to, list(type = e$type, sender = uid, content = e$content))
            mx_sas_outgoing(from, e$id)
        }
    }
    mx_sas_accept(sa)
    for (i in 1:3) {transfer(sa, sb); transfer(sb, sa)}
    expect_identical(mx_sas_status(sa)$decimal, mx_sas_status(sb)$decimal)
    mx_sas_confirm(sa, TRUE)
    mx_sas_confirm(sb, TRUE)
    transfer(sa, sb)
    transfer(sb, sa, device_only = TRUE)
    expect_true(mx_sas_status(sa)$peer_mac_valid)
    expect_identical(mx_sas_status(sa)$phase, "verified")
    expect_equal(uploads, 0L)
    mx_sas_record_trust(sa, client, store)
    expect_true(mx_sas_status(sa)$local_trust_recorded)
    expect_equal(uploads, 1L)
    expect_true(queries >= 3L)
    public <- mx.crypto::mxc_signing_key_public(signing$self_signing)
    expect_true(mx.client:::mx_crypto_signature_valid(devices$B, uid, public))
    verified <- mx_crypto_known_devices(client, uid,
        self_master_key = mx.crypto::mxc_signing_key_public(signing$master))
    target <- Filter(function(d) d$device_id == "B", verified)
    expect_equal(length(target), 1L)
    expect_true(target[[1]]$cross_signed)
    mx_sas_record_trust(sa, client, store)
    expect_equal(uploads, 1L)
})
