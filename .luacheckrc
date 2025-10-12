-- .luacheckrc
-- For configuration options, see https://luacheck.readthedocs.io/en/stable/config.html

-- List of recognized globals.
read_globals = {
  "hs",
  "spoon"
}

-- Don't warn about unused arguments.
unused_args = "allow"

-- Files to ignore.
exclude_files = {
  "Spoons/"
}
