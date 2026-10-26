% tinyrox says don't edit this manually, but it can't stop you!
\name{mx_upload_encrypted}
\alias{mx_upload_encrypted}
\title{Upload an encrypted Matrix attachment}
\usage{
mx_upload_encrypted(
  client,
  path,
  body = basename(path),
  msgtype = NULL,
  content_type = NULL,
  info = list(),
  max_bytes = 25 * 1024^2
)
}
\arguments{
\item{client}{Matrix client config.}

\item{path}{Path of the file to upload.}

\item{body}{Display filename or caption, inside the encrypted event.}

\item{msgtype}{Media message type, or NULL to derive it from the MIME type.}

\item{content_type}{MIME type, or NULL to guess from the file extension.}

\item{info}{Extra media metadata, inside the encrypted event.}

\item{max_bytes}{Maximum plaintext size in bytes, default 25 MiB. Encryption
uses memory; larger files require an explicit higher limit.}
}
\value{
Matrix message content with \code{file} instead of \code{url}.
}
\description{
Uploads ciphertext only, with a generic filename and content type.
Returns content to pass to \code{mx_send_encrypted()} using the caller's
existing account and sessions. The return value includes a secret key:
never post it in an unencrypted event. Does not open a crypto store.
}
