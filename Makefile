# Local driver for the skills → plugins sync. CI does the same via
# .github/workflows/sync-skills.yml; these targets let you test against local
# checkouts of the consumer plugins.
#
# Override paths/tag as needed:
#   make sync-cursor CURSOR=../cursor-plugin TAG=v1.2.3
#   make sync        CURSOR=../cursor-plugin CLAUDE=../claude-plugin

CURSOR ?= ../cursor-plugin
CLAUDE ?= ../claude-plugin
TAG    ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

.PHONY: help sync sync-cursor sync-claude check-drift check-drift-cursor check-drift-claude hash

help: ## Show this help
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

sync: sync-cursor sync-claude ## Sync skills into both local plugin checkouts

sync-cursor: ## Vendor skills into $(CURSOR) (host: cursor)
	scripts/sync-skills.sh --host cursor --target "$(CURSOR)" --tag "$(TAG)"

sync-claude: ## Vendor skills + command stubs into $(CLAUDE) (host: claude)
	scripts/sync-skills.sh --host claude --target "$(CLAUDE)" --tag "$(TAG)"

check-drift: check-drift-cursor check-drift-claude ## Drift-check both local plugin checkouts

check-drift-cursor: ## Fail if $(CURSOR) vendored skills drifted from their stamp
	scripts/check-drift.sh --target "$(CURSOR)" --canonical .

check-drift-claude: ## Fail if $(CLAUDE) vendored skills drifted from their stamp
	scripts/check-drift.sh --target "$(CLAUDE)" --canonical .

hash: ## Print the canonical skills content hash
	scripts/skills-hash.sh .
