# SWELibApp — Productivity Tracker
# Lean 4 with formal specs via SWELib

.PHONY: build build-spec build-impl build-server clean deploy status stop delete update
.PHONY: up down health reset logs

# ── Build ──────────────────────────────────────────────────────────

build: build-spec build-impl

build-spec:
	lake build Spec

build-impl:
	lake build deploy

build-server:
	lake build server

# ── Local Docker ───────────────────────────────────────────────────

up:
	docker compose up -d --build

down:
	docker compose down

health:
	@curl -sf http://localhost:8000/health && echo || echo "Server not responding"

reset:
	docker compose down -v
	docker compose up -d --build

logs:
	docker compose logs -f

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
