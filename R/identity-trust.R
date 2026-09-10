# Authenticate other users' master keys through our locally pinned master
# and its user-signing key. Malformed or missing links never grant trust.
mx_crypto_trusted_master_keys <- function(master_keys, user_signing_keys,
                                            self_id, self_master_key) {
    valid <- tryCatch({
        self <- mx_crypto_cross_signing_public(
            master_keys[[self_id]], self_id, "master")
        user <- user_signing_keys[[self_id]]
        signing_key <- mx_crypto_cross_signing_public(
            user, self_id, "user_signing")
        if (!identical(self, self_master_key) ||
            !mx_crypto_signature_valid(user, self_id, self_master_key)) {
            return(list())
        }
        out <- stats::setNames(list(self_master_key), self_id)
        for (uid in setdiff(names(master_keys), self_id)) {
            peer <- master_keys[[uid]]
            public <- tryCatch(mx_crypto_cross_signing_public(
                peer, uid, "master"), error = function(e) NULL)
            if (!is.null(public) &&
                mx_crypto_signature_valid(peer, self_id, signing_key)) {
                out[[uid]] <- public
            }
        }
        out
    }, error = function(e) list())
    valid
}
