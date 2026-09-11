if (isTRUE(getOption("rapt.enabled"))) rapt::disable()
description <- read.dcf("DESCRIPTION")
requirements <- trimws(strsplit(paste(description[1, c("Imports", "Suggests")],
    collapse = ","), ",", fixed = TRUE)[[1]])
floor_for <- function(pkg) {
    prefix <- paste0(pkg, " (>= ")
    entry <- requirements[startsWith(requirements, prefix)]
    if (length(entry) != 1L || !endsWith(entry, ")")) {
        stop("Cannot read Matrix dependency floor from DESCRIPTION: ", pkg)
    }
    substr(entry, nchar(prefix) + 1L, nchar(entry) - 1L)
}
floors <- setNames(vapply(c("mx.api", "mx.crypto"), floor_for, character(1)),
    c("mx.api", "mx.crypto"))
ref <- Sys.getenv("MX_CRYPTO_REF")
if (!grepl("^[0-9a-f]{40}$", ref)) stop("CI requires an immutable mx.crypto commit")
utils::install.packages("mx.api",
    repos = c("https://cran.r-project.org", "https://cornball-ai.github.io/drat"),
    type = "source", dependencies = FALSE)
utils::install.packages(paste0("https://github.com/cornball-ai/mx.crypto/archive/",
    ref, ".tar.gz"), repos = NULL, type = "source", dependencies = FALSE)
for (pkg in names(floors)) {
    if (!requireNamespace(pkg, quietly = TRUE) ||
        utils::packageVersion(pkg) < floors[[pkg]]) {
        stop("CI needs ", pkg, " >= ", floors[[pkg]])
    }
    message(pkg, " ", utils::packageVersion(pkg), " at ", find.package(pkg))
}
stopifnot(utils::packageVersion("mx.crypto") >= "0.2.1.2",
    "mxc_sas_commitment" %in% getNamespaceExports("mx.crypto"))
