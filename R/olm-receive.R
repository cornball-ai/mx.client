# An Olm session is bidirectional. The two persisted maps describe who
# initiated it, not which direction its messages can travel. Try both maps
# before consuming another one-time key; failed decrypts leave the session
# unchanged in vodozemac.
olm_receive <- function(account, sender, msg, sessions = list()) {
    if (!is.list(msg) || !is.numeric(msg$type) || length(msg$type) != 1L ||
        !isTRUE(msg$type %in% c(0L, 1L)) ||
        !is.character(msg$body) || length(msg$body) != 1L ||
        is.na(msg$body) || !is.character(sender) || length(sender) != 1L ||
        is.na(sender) || !nzchar(sender)) {
        warning("mx.client: dropping malformed Olm to-device message",
                call. = FALSE)
        return(NULL)
    }
    n_tried <- 0L
    for (session in sessions) {
        if (is.null(session)) next
        n_tried <- n_tried + 1L
        plaintext <- tryCatch(
            mx.crypto::mxc_olm_decrypt(session, msg$type, msg$body),
            error = function(e) NULL)
        if (!is.null(plaintext)) {
            return(list(session = session, plaintext = plaintext, new = FALSE))
        }
    }
    create_err <- NULL
    if (msg$type == 0L) {
        # A repeated prekey may no longer have an OTK. Do not let that
        # failure abort a sync batch whose earlier messages advanced ratchets.
        result <- tryCatch(mx.crypto::mxc_olm_create_inbound(
            account, peer_curve25519 = sender, prekey_b64 = msg$body),
            error = function(e) {
                create_err <<- conditionMessage(e)
                NULL
            })
        if (!is.null(result)) {
            result$new <- TRUE
            return(result)
        }
    }
    # The type and the count of sessions actually tried turn a silent "it
    # just failed" into something diagnosable: a type-1 reply that no stored
    # session decrypts means we are missing the session the sender chose
    # (keep every session per peer and try them all); a type-0 failure
    # carries the create_inbound error (a spent or malformed one-time key).
    warning("mx.client: cannot decrypt Olm to-device message (type ",
            msg$type, ", ", n_tried, " session(s) tried",
            if (!is.null(create_err)) paste0(", create_inbound: ", create_err)
            else "", "); dropping it", call. = FALSE)
    NULL
}

# Parsing follows a successful, state-mutating decrypt. A malformed payload
# must not discard the updated session or prevent processing the next event.
olm_decode <- function(plaintext) {
    decoded <- tryCatch(jsonlite::fromJSON(rawToChar(plaintext),
                                         simplifyVector = FALSE),
                        error = function(e) NULL)
    if (!is.list(decoded)) {
        warning("mx.client: dropping malformed Olm plaintext",
                call. = FALSE)
        return(NULL)
    }
    decoded
}
