test_all <- (identical (Sys.getenv ("MPADGE_LOCAL"), "true") ||
    identical (Sys.getenv ("GITHUB_JOB"), "test-coverage") ||
    identical (Sys.getenv ("GITHUB_JOB"), "pkgcheck"))

skip_if (!test_all)

test_that ("pkgcheck", {

    withr::local_envvar (list ("PKGCHECK_SRR_REPORT_FILE" = "report.html"))
    withr::local_envvar (list ("PKGCHECK_TEST_NETWORK_FILE" = "network.html"))
    withr::local_envvar (list (
        "PKGCHECK_CACHE_DIR" =
            file.path (tempdir (), "pkgcheck")
    ))
    withr::local_envvar (list ("GITHUB_ACTIONS" = "true"))
    withr::local_envvar (list ("GITHUB_REPOSITORY" = "org/repo"))

    pkgname <- "testpkgchecknotapkg"
    d <- srr::srr_stats_pkg_skeleton (pkg_name = pkgname)
    # Add memoise to check global assign in memoised fns:
    f_desc <- fs::path (d, "DESCRIPTION")
    desc <- readLines (f_desc)
    i <- grep ("Rcpp$", desc) [1]

    # Add lots of 'Imports' to fail 'pkgcheck_num_imports' #218:
    num_deps_to_add <- 20L
    deps_add <- c (rep ("    memoise,", num_deps_to_add), "    Rcpp")

    desc <- c (
        desc [seq_len (i - 1)],
        deps_add,
        desc [seq (i + 1, length (desc))]
    )
    writeLines (desc, f_desc)
    # Define memoised fn in new 'zzz.R' file:
    f_zzz <- fs::path (d, "zzz.R")
    zzz <- c (
        ".onLoad <- function(libname, pkgname) {",
        "    test_fn <<- memoise::memoise(test_fn)",
        "}"
    )
    writeLines (zzz, f_zzz)

    x <- capture.output (
        roxygen2::roxygenise (d),
        type = "message"
    )

    expect_gt (length (x), 10)
    expect_true (any (grepl ("srrstats", x)))

    expect_output (
        checks <- pkgcheck (d)
    )
    expect_type (checks, "list")

    # goodpractice -> rcmdcheck fails on some machines for reasons that can't be
    # controlled (such as not being able to find "MASS" pkg).
    checks$goodpractice <- NULL
    # Checks on systems without the right API keys may fail checks which rely on
    # URL queries, so these are manually reset here:
    checks$checks$pkgname_available <- TRUE
    checks$info$badges <- NULL # then fails CI checks

    items <- c ("pkg", "info", "checks", "meta")
    expect_named (checks, items)

    items <- c (
        "name", "path", "version", "url", "BugReports",
        "license", "summary", "dependencies", "external_calls",
        "external_fns"
    )
    expect_named (checks$pkg, items)

    items <- c (
        "fn_names",
        "git",
        "network_file",
        "pkgdown_concepts",
        "pkgstats",
        "renv_activated",
        "srr"
    )
    expect_identical (sort (names (checks$info)), sort (items))

    md <- checks_to_markdown (checks, render = FALSE)

    a <- attributes (md)
    expect_gt (length (a), 0L)
    expect_true (
        all (c (
            "checks_okay",
            "is_noteworthy",
            "network_file",
            "srr_report_file"
        ) %in% names (a))
    )

    # *****************************************************************
    # ***********************   SNAPSHOT TEST   ***********************
    # *****************************************************************

    # paths in these snapshots are not stable on windows, so skipped here
    skip_on_os ("windows")

    md <- edit_markdown (md) # from clean-snapshots.R

    md_dir <- withr::local_tempdir ()
    writeLines (md, con = file.path (md_dir, "checks.md"))

    # Redact out variable git hashes:
    testthat::expect_snapshot_file (file.path (md_dir, "checks.md"))

    h <- render_md2html (md, open = FALSE)
    f <- file.path (md_dir, "checks.html")
    file.rename (h, f)
    edit_html (f) # from clean-snapshots.R

    testthat::expect_snapshot_file (f)

    fs::dir_delete (d)
})

test_that ("pkgcheck without goodpractice", {
    pkgname <- paste0 (
        sample (c (letters, LETTERS), 8),
        collapse = ""
    )
    d <- srr::srr_stats_pkg_skeleton (pkg_name = pkgname)

    x <- capture.output (
        roxygen2::roxygenise (d),
        type = "message"
    )

    withr::local_envvar (list (
        "PKGCHECK_CACHE_DIR" =
            file.path (tempdir (), "pkgcheck")
    ))

    expect_output (
        checks <- pkgcheck (d, goodpractice = FALSE)
    )

    # items from above including goodpractice:
    items <- c ("pkg", "info", "checks", "meta", "goodpractice")
    expect_false (all (items %in% names (checks)))
    items <- c ("pkg", "info", "checks", "meta")
    expect_true (all (items %in% names (checks)))

    fs::dir_delete (d)
})
