# Matrix's fixed SAS alphabet. Escapes keep the R source ASCII-only.
sas_emoji <- function() {
    codepoints <- c(0x1f436, 0x1f431, 0x1f981, 0x1f40e, 0x1f984, 0x1f437,
        0x1f418, 0x1f430, 0x1f43c, 0x1f413, 0x1f427, 0x1f422, 0x1f41f,
        0x1f419, 0x1f98b, 0x1f337, 0x1f333, 0x1f335, 0x1f344, 0x1f30f,
        0x1f319, 0x2601, 0x1f525, 0x1f34c, 0x1f34e, 0x1f353, 0x1f33d,
        0x1f355, 0x1f382, 0x2764, 0x1f600, 0x1f916, 0x1f3a9, 0x1f453,
        0x1f527, 0x1f385, 0x1f44d, 0x2602, 0x231b, 0x23f0, 0x1f381,
        0x1f4a1, 0x1f4d5, 0x270f, 0x1f4ce, 0x2702, 0x1f512, 0x1f511,
        0x1f528, 0x260e, 0x1f3c1, 0x1f682, 0x1f6b2, 0x2708, 0x1f680,
        0x1f3c6, 0x26bd, 0x1f3b8, 0x1f3ba, 0x1f514, 0x2693, 0x1f3a7,
        0x1f4c1, 0x1f4cc)
    emoji <- intToUtf8(codepoints, multiple = TRUE)
    variation <- c(22L, 30L, 38L, 44L, 46L, 50L, 54L)
    emoji[variation] <- paste0(emoji[variation], "\ufe0f")
    labels <- c("Dog", "Cat", "Lion", "Horse", "Unicorn", "Pig", "Elephant",
        "Rabbit", "Panda", "Rooster", "Penguin", "Turtle", "Fish", "Octopus",
        "Butterfly", "Flower", "Tree", "Cactus", "Mushroom", "Globe", "Moon",
        "Cloud", "Fire", "Banana", "Apple", "Strawberry", "Corn", "Pizza",
        "Cake", "Heart", "Smiley", "Robot", "Hat", "Glasses", "Spanner",
        "Santa", "Thumbs Up", "Umbrella", "Hourglass", "Clock", "Gift",
        "Light Bulb", "Book", "Pencil", "Paperclip", "Scissors", "Lock", "Key",
        "Hammer", "Telephone", "Flag", "Train", "Bicycle", "Aeroplane",
        "Rocket", "Trophy", "Ball", "Guitar", "Trumpet", "Bell", "Anchor",
        "Headphones", "Folder", "Pin")
    list(emoji = emoji, labels = labels)
}

sas_display <- function(bytes) {
    b <- as.integer(bytes)
    stopifnot(length(b) == 6L, all(b >= 0L & b <= 255L))
    decimal <- c(b[1] * 32L + b[2] %/% 8L,
        (b[2] %% 8L) * 1024L + b[3] * 4L + b[4] %/% 64L,
        (b[4] %% 64L) * 128L + b[5] %/% 2L) + 1000L
    indexes <- c(b[1] %/% 4L, (b[1] %% 4L) * 16L + b[2] %/% 16L,
        (b[2] %% 16L) * 4L + b[3] %/% 64L, b[3] %% 64L,
        b[4] %/% 4L, (b[4] %% 4L) * 16L + b[5] %/% 16L,
        (b[5] %% 16L) * 4L + b[6] %/% 64L) + 1L
    alphabet <- sas_emoji()
    list(decimal = decimal, emoji = alphabet$emoji[indexes],
        descriptions = alphabet$labels[indexes])
}

#' Inspect a Matrix SAS verification transaction
#'
#' Display codes only on the operator's trusted console, never in the Matrix
#' conversation being verified. A verified SAS is distinct from a recorded
#' local trust signature and from the peer's completion acknowledgement.
#' @param sas An in-memory SAS transaction.
#' @return A list with identities, phase, comparison values, local confirmation,
#'   peer MAC validity, local trust status, peer completion, and cancellation code.
#'   cancel_detail identifies a locally diagnosed missing peer master proof.
#' @export
mx_sas_status <- function(sas) {
    sas_check(sas)
    display <- if (sas$phase %in% c("sas", "confirmed", "verified", "done")) {
        sas_display(sas$display_bytes)
    } else list()
    if (!"decimal" %in% sas$displays) display$decimal <- NULL
    if (!"emoji" %in% sas$displays) {
        display$emoji <- display$descriptions <- NULL
    }
    c(list(user_id = sas$user_id, device_id = sas$device_id,
        peer_user_id = sas$peer_user_id, peer_device_id = sas$peer_device_id,
        transaction_id = sas$transaction_id, phase = sas$phase), display,
        list(confirmed = sas$confirmed, peer_mac_valid = sas$peer_mac_valid,
            local_trust_recorded = sas$local_trust_recorded,
            peer_done = sas$peer_done, cancel_code = sas$cancel_code,
            cancel_detail = sas$cancel_detail))
}
