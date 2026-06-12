
if (requireNamespace("tinytest", quietly = TRUE)) {
  Sys.setenv(R_USER_CACHE_DIR  = tempfile("mx.client_cache_"),
             R_USER_DATA_DIR   = tempfile("mx.client_data_"),
             R_USER_CONFIG_DIR = tempfile("mx.client_config_"))
  tinytest::test_package("mx.client")
}
