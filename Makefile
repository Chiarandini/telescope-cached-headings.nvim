.PHONY: test

test:
	nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" 2>&1; true
