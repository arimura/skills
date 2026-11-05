# Package each skill as dist/<name>.zip for upload to claude.ai
# (one skill per ZIP, with the skill folder at the ZIP root).
#   make                         # all skills
#   make dist/<name>.zip         # one skill
SHELL := bash
SKILLS := $(notdir $(wildcard skills/*))

.PHONY: package clean FORCE
package: $(SKILLS:%=dist/%.zip)

# Checks claude.ai's limits: name equals the folder name; description is 1-200 chars.
dist/%.zip: FORCE
	@name=$$(sed -n 's/^name: //p' skills/$*/SKILL.md); [ "$$name" = "$*" ] || { echo "FAIL $*: name '$$name' must equal the folder name" >&2; exit 1; }
	@n=$$(sed -n 's/^description: //p' skills/$*/SKILL.md | tr -d '\n' | LC_ALL=C tr -d '\200-\277' | wc -c); [ $$n -ge 1 ] && [ $$n -le 200 ] || { echo "FAIL $*: description must be 1-200 chars (is $$((n)))" >&2; exit 1; }
	@mkdir -p dist && rm -f $@ && cd skills && zip -qrX ../$@ $* -x '*.DS_Store'
	@echo "ok   $@"

clean:
	rm -rf dist
