#!/usr/bin/env bash
#
# Print human-readable kmp.new (https://kmp.jetbrains.com) instructions for the user.
# JetBrains' wizard is a Next.js SPA without query-param support, so we cannot
# pre-fill the form via URL — we give the user explicit instructions instead.
#
# Usage:
#   kmp-new-url.sh "<APP_NAME>" "<BASE_PACKAGE>" "<PLATFORMS_CSV>" "<LIBS_CSV>"
#
#   PLATFORMS_CSV: comma-separated subset of {android,ios,desktop,web}
#   LIBS_CSV:      comma-separated optional libs the wizard offers
#                  (ktor, sqldelight). Locked-stack libs are added by the overlay
#                  step, not by the wizard.

set -euo pipefail

app_name="${1:-}"
base_package="${2:-}"
platforms_csv="${3:-android,ios}"
libs_csv="${4:-}"

cat <<MSG

==============================================================================
                       kmp-forge — kmp.new instructions
==============================================================================

Open in your browser:

    https://kmp.jetbrains.com/

Configure the wizard as follows:

  • Project name:        ${app_name}
  • Project ID:          ${base_package}
  • Platforms (check):   ${platforms_csv//,/ , }
$( [[ -n "$libs_csv" ]] && echo "  • Libraries (check):   ${libs_csv//,/ , }" )

Click "Download" and remember the path to the .zip in ~/Downloads/.

Press Enter once the download is done.
==============================================================================
MSG
