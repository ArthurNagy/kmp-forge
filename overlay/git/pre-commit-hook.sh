#!/usr/bin/env bash
# Installed at .git/hooks/pre-commit by /kmp-forge-init.
# Set SKIP_GITLEAKS=1 to bypass for an emergency commit (rotate any leaked secret afterward).
set -euo pipefail

if [[ "${SKIP_GITLEAKS:-}" == "1" ]]; then
    exit 0
fi

if ! command -v gitleaks >/dev/null; then
    echo "warning: gitleaks not installed; install with: brew install gitleaks"
    echo "         skipping secret scan for this commit."
    exit 0
fi

gitleaks protect --staged --config .gitleaks.toml --no-banner --redact
