# SWELibApp — Productivity Tracker
# Lean 4 with formal specs via SWELib

.PHONY: build build-spec build-impl clean deploy status stop delete update

# ── Build ──────────────────────────────────────────────────────────

build: build-spec build-impl

build-spec:
	lake build Spec

build-impl:
	lake build deploy

# ── Deploy (requires GCP_PROJECT env var) ──────────────────────────

deploy: build-impl
	.lake/build/bin/deploy deploy

status: build-impl
	.lake/build/bin/deploy status

stop: build-impl
	.lake/build/bin/deploy stop

delete: build-impl
	.lake/build/bin/deploy delete

# ── Clean ──────────────────────────────────────────────────────────

clean:
	lake clean

# ── Lake update ────────────────────────────────────────────────────

update:
	lake update
