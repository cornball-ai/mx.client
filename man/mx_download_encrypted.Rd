% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_download_encrypted}
\alias{mx_download_encrypted}
\title{Download and verify an encrypted Matrix attachment}
\usage{
mx_download_encrypted(client, file, dest, max_bytes = 25 * 1024^2)
}
\arguments{
\item{client}{Matrix client config.}

\item{file}{Matrix v2 encrypted-file metadata, including its \code{url}.}

\item{dest}{Destination path. Its parent directory must exist.}

\item{max_bytes}{Maximum downloaded size to read into memory, default 25
MiB. This is checked on disk before decryption, not a network transfer cap.}
}
\value{
Destination path, invisibly.
}
\description{
Downloads ciphertext into a private temporary directory, verifies its
SHA-256 digest and decrypts it before replacing the destination. Failure
leaves an existing destination unchanged. Metadata must come from an
authenticated encrypted room event. Does not open a crypto store.
}
