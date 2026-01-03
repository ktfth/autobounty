.PHONY: help build up down run resume report all clean check-crlf

help:
	@echo "AutoBounty - Visual Bug Bounty Recon Pipeline"
	@echo ""
	@echo "Targets:"
	@echo "  make build   - Build runner Docker image"
	@echo "  make up      - Start containers (daemon)"
	@echo "  make down    - Stop containers"
	@echo "  make run     - Execute recon pipeline (new run)"
	@echo "  make resume  - Resume previous run (skip cached steps)"
	@echo "  make report  - Generate markdown report"
	@echo "  make all     - Build + run + report (complete pipeline)"
	@echo "  make clean   - Remove all output files"
	@echo "  make check-crlf - Check for CRLF in scripts"
	@echo ""
	@echo "Environment: .env file (copy from .env.example)"

build:
	@echo "Building runner image..."
	docker compose build runner

up:
	@echo "Starting containers..."
	docker compose up -d

down:
	@echo "Stopping containers..."
	docker compose down

run: up
	@echo "Running recon pipeline (new run)..."
	docker compose run --rm runner bash -lc "bash /work/scripts/10_run_pipeline.sh"

resume: up
	@echo "Resuming previous pipeline run (using cache)..."
	docker compose run --rm -e RESUME=true runner bash -lc "bash /work/scripts/10_run_pipeline.sh"

report:
	@echo "Generating report..."
	docker compose run --rm runner bash -lc "bash /work/scripts/20_build_reports.sh"

all: build run report
	@echo "Pipeline complete! Check output/<RUN_ID>/REPORT.md"

clean:
	@echo "Removing output files..."
	rm -rf output/*
	@echo "Clean complete"

check-crlf:
	@echo "Checking for CRLF in scripts..."
	@for f in scripts/*.sh; do \
		if file "$$f" | grep -q CRLF; then \
			echo "CRLF found in $$f"; \
			exit 1; \
		fi; \
	done
	@echo "No CRLF detected"
