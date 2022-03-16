# Build and test
build :; nile compile
test  :; pytest -s tests/ -W ignore::DeprecationWarning