# source("renv/activate.R")


message(">>> .Rprofile is loading...") # Add this at the top

source("renv/activate.R")

if (interactive() && Sys.getenv("RSTUDIO") == "") {
    message(">>> Trying to source init.R...") # Add this
    init_path <- file.path(
        Sys.getenv(if (.Platform$OS.type == "windows") "USERPROFILE" else "HOME"),
        ".vscode-R", "init.R"
    )
    source(init_path)
    message(">>> init.R sourced, calling .First.sys()...") # Add this
    .First.sys()
}
