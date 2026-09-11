pkg <- "mx.client"
check_dir <- normalizePath(paste0(pkg, ".Rcheck"), mustWork = TRUE)
lines <- readLines(file.path(check_dir, "00check.log"), warn = FALSE)
status <- grep("^Status:", lines, value = TRUE)
if (length(status) != 1L || any(grepl("ERROR|WARNING", status))) {
    stop("Missing or failed R CMD check result: ", paste(status, collapse = "; "))
}
cat(status, "\n")
.libPaths(c(check_dir, .libPaths()))
library(pkg, character.only = TRUE, lib.loc = check_dir)
expected <- unname(read.dcf("DESCRIPTION")[1, "Version"])
stopifnot(identical(as.character(utils::packageVersion(pkg)), expected),
    utils::packageVersion("mx.crypto") >= "0.2.2",
    "mxc_sas_commitment" %in% getNamespaceExports("mx.crypto"))
cat("Testing checked build:", find.package(pkg), expected, "\n")
cat("Crypto build:", find.package("mx.crypto"),
    as.character(utils::packageVersion("mx.crypto")), "\n")
for (file in c("test_sas.R", "test_sas_identity.R", "test_sas_own_device.R",
    "test_sas_transport.R", "test_user_verification.R")) {
    result <- tinytest::run_test_file(file.path("inst", "tinytest", file),
        at_home = FALSE, verbose = 0, color = FALSE)
    print(result)
    if (!length(result) || !tinytest::all_pass(result)) {
        stop("SAS/identity coverage failed or was skipped: ", file)
    }
}
