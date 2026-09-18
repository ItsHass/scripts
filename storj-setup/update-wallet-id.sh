#!/usr/bin/env bash

###############################################################################
#
#  STORJ WALLET REPLACEMENT / CONTAINER REBUILD SCRIPT
#
#  USAGE
#  -----
#      ./storj-wallet-replace.sh --directory /path/dir --wallet 0xNEW
#
#  --directory is REQUIRED and points directly at the folder containing
#  standard-variables.sh and standard-02-2025.sh for this node. No Docker
#  mount inspection, auto-detection, or runtime CLI-argument checking is
#  performed - standard-variables.sh is the sole source of truth.
#
###############################################################################

set -o pipefail

###############################################################################
# CONFIGURATION
###############################################################################

# ===========================================================================
# PUT THE NEW WALLET HERE
# ===========================================================================

NEW_WALLET="PASTE_NEW_WALLET_HERE"

# Expected files
VARIABLE_FILE_NAME="standard-variables.sh"
LAUNCHER_FILE_NAME="standard-02-2025.sh"

# Expected Docker image
EXPECTED_IMAGE="storjlabs/storagenode"

# Container startup timeout
START_TIMEOUT=90

###############################################################################
# DISPLAY
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
RESET='\033[0m'

###############################################################################
# FUNCTIONS
###############################################################################

info() {
    echo -e "${CYAN}[INFO]${RESET} $*"
}

ok() {
    echo -e "${GREEN}[  OK ]${RESET} $*"
}

warn() {
    echo -e "${YELLOW}[ WARN ]${RESET} $*"
}

fail() {
    echo -e "${RED}[FAIL ]${RESET} $*"
}

gate() {
    echo
    echo -e "${MAGENTA}======================================================================${RESET}"
    echo -e "${MAGENTA}  GATE: $*${RESET}"
    echo -e "${MAGENTA}======================================================================${RESET}"
    echo
}

abort() {
    fail "$*"
    echo
    echo -e "${RED}************************************************************************${RESET}"
    echo -e "${RED}  SCRIPT ABORTED - NO FURTHER ACTION WILL BE TAKEN${RESET}"
    echo -e "${RED}************************************************************************${RESET}"
    echo
    exit 1
}

usage() {
    cat <<EOF
Usage: $0 --directory /path/to/storj/dir [--wallet 0xADDRESS]

  --directory DIR   REQUIRED. The directory containing this node's
                     standard-variables.sh and standard-02-2025.sh.
                     Used directly - no Docker mount inspection or
                     auto-detection is performed.

  --wallet ADDR     The new wallet value to write into the existing
                     Wallet= line. Overrides the NEW_WALLET value hardcoded
                     at the top of this script, so the same script file can
                     be reused unmodified across multiple nodes - just pass
                     a different --directory and --wallet per node.

                     If omitted, the hardcoded NEW_WALLET in the script is
                     used instead. One of the two must resolve to a real
                     value or the script aborts.

  -h, --help        Show this help text.
EOF
}

###############################################################################
# ARGUMENT PARSING
###############################################################################

DIRECTORY_ARG=""
WALLET_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --directory)
            DIRECTORY_ARG="${2:-}"
            if [[ -z "$DIRECTORY_ARG" ]]; then
                fail "--directory requires a path argument."
                usage
                exit 1
            fi
            shift 2
            ;;
        --directory=*)
            DIRECTORY_ARG="${1#--directory=}"
            shift
            ;;
        --wallet)
            WALLET_ARG="${2:-}"
            if [[ -z "$WALLET_ARG" ]]; then
                fail "--wallet requires a value argument."
                usage
                exit 1
            fi
            shift 2
            ;;
        --wallet=*)
            WALLET_ARG="${1#--wallet=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

# Strip any trailing slash for consistent comparisons later.
DIRECTORY_ARG="${DIRECTORY_ARG%/}"

# A --wallet argument on the command line overrides the hardcoded
# NEW_WALLET value at the top of the script, so the same script file
# can be reused as-is across multiple nodes.
WALLET_SOURCE="script default (NEW_WALLET)"

if [[ -n "$WALLET_ARG" ]]; then
    NEW_WALLET="$WALLET_ARG"
    WALLET_SOURCE="--wallet argument"
fi

###############################################################################
# HEADER
###############################################################################

clear 2>/dev/null || true

echo
echo -e "${WHITE}======================================================================${RESET}"
echo -e "${WHITE}        STORJ WALLET REPLACEMENT / CONTAINER REBUILD${RESET}"
echo -e "${WHITE}======================================================================${RESET}"
echo
echo " Host       : $(hostname)"
echo " User       : $(whoami)"
echo " Date       : $(date)"
echo

if [[ -n "$DIRECTORY_ARG" ]]; then
    echo " --directory provided : $DIRECTORY_ARG"
else
    echo " --directory provided : (none - script will abort, --directory is required)"
fi

echo " Wallet source        : $WALLET_SOURCE"

echo
echo -e "${BLUE} This script is deliberately gated and will refuse to guess.${RESET}"
echo

###############################################################################
# GATE 1 - ROOT
###############################################################################

gate "ROOT PRIVILEGES"

if [[ "$EUID" -ne 0 ]]; then
    abort "This script must be run as root."
fi

ok "Running as root."

###############################################################################
# GATE 2 - DOCKER
###############################################################################

gate "DOCKER AVAILABILITY"

if ! command -v docker >/dev/null 2>&1; then
    abort "Docker command was not found."
fi

ok "Docker command found."

if ! docker info >/dev/null 2>&1; then
    abort "Docker daemon is not accessible."
fi

ok "Docker daemon is accessible."

###############################################################################
# GATE 3 - NEW WALLET
###############################################################################

gate "NEW WALLET VALIDATION"

echo "New Wallet source: $WALLET_SOURCE"
echo
echo "New Wallet to be written:"
echo
echo "    $NEW_WALLET"
echo

if [[ "$NEW_WALLET" == "PASTE_NEW_WALLET_HERE" ]]; then
    abort "No wallet was provided. Either pass --wallet 0xADDRESS on the command line, or set NEW_WALLET at the top of this script."
fi

if [[ -z "$NEW_WALLET" ]]; then
    abort "NEW_WALLET is empty."
fi

# Basic Ethereum-style wallet validation.
if [[ ! "$NEW_WALLET" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    warn "Wallet does not match the expected 0x + 40 hexadecimal format."
    echo
    read -r -p "Type ACCEPT to continue anyway: " WALLET_ACCEPT

    if [[ "$WALLET_ACCEPT" != "ACCEPT" ]]; then
        abort "Wallet validation rejected."
    fi
else
    ok "Wallet format looks valid."
fi

###############################################################################
# GATE 4 - FIND RUNNING STORJ CONTAINER
###############################################################################

gate "LOCATING RUNNING STORJ CONTAINER"

echo "Running containers:"
echo

docker ps \
    --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}'

echo

mapfile -t STORJ_CONTAINERS < <(
    docker ps \
        --format '{{.ID}} {{.Image}} {{.Names}}' |
    awk '$2 ~ /^storjlabs\/storagenode/ {print $1}'
)

if [[ "${#STORJ_CONTAINERS[@]}" -eq 0 ]]; then
    abort "No running storjlabs/storagenode container was found."
fi

if [[ "${#STORJ_CONTAINERS[@]}" -gt 1 ]]; then

    fail "Multiple running Storj containers were found."
    echo

    for ID in "${STORJ_CONTAINERS[@]}"; do
        docker inspect \
            --format 'ID={{.Id}} NAME={{.Name}} IMAGE={{.Config.Image}}' \
            "$ID"
    done

    echo
    abort "Refusing to guess which container should be modified."
fi

CONTAINER_ID="${STORJ_CONTAINERS[0]}"

CONTAINER_NAME=$(
    docker inspect \
        --format '{{.Name}}' \
        "$CONTAINER_ID" |
    sed 's#^/##'
)

CONTAINER_IMAGE=$(
    docker inspect \
        --format '{{.Config.Image}}' \
        "$CONTAINER_ID"
)

CONTAINER_STATUS=$(
    docker inspect \
        --format '{{.State.Status}}' \
        "$CONTAINER_ID"
)

ok "Storj container found."

echo
echo "    Container ID : $CONTAINER_ID"
echo "    Name         : $CONTAINER_NAME"
echo "    Image        : $CONTAINER_IMAGE"
echo "    Status       : $CONTAINER_STATUS"
echo

if [[ "$CONTAINER_IMAGE" != ${EXPECTED_IMAGE}* ]]; then
    abort "Container image does not match $EXPECTED_IMAGE."
fi

###############################################################################
# GATE 5 - IDENTIFY STORJ DIRECTORY (FROM --directory)
###############################################################################

gate "IDENTIFYING STORJ DIRECTORY"

if [[ -z "$DIRECTORY_ARG" ]]; then
    abort "No --directory was provided. Re-run with --directory /path/to/storj/dir (the folder containing $VARIABLE_FILE_NAME and $LAUNCHER_FILE_NAME)."
fi

echo "Directory provided via --directory:"
echo
echo "    $DIRECTORY_ARG"
echo

if [[ ! -d "$DIRECTORY_ARG" ]]; then
    abort "--directory '$DIRECTORY_ARG' does not exist or is not a directory."
fi

VARIABLE_FOUND="NO"
LAUNCHER_FOUND="NO"

if [[ -f "$DIRECTORY_ARG/$VARIABLE_FILE_NAME" ]]; then
    VARIABLE_FOUND="YES"
fi

if [[ -f "$DIRECTORY_ARG/$LAUNCHER_FILE_NAME" ]]; then
    LAUNCHER_FOUND="YES"
fi

echo "    standard-variables.sh : $VARIABLE_FOUND"
echo "    standard-02-2025.sh   : $LAUNCHER_FOUND"
echo

if [[ "$VARIABLE_FOUND" != "YES" ]]; then
    abort "--directory '$DIRECTORY_ARG' does not contain $VARIABLE_FILE_NAME."
fi

if [[ "$LAUNCHER_FOUND" != "YES" ]]; then
    abort "--directory '$DIRECTORY_ARG' does not contain $LAUNCHER_FILE_NAME."
fi

ok "Both required files were found in the specified directory."

###############################################################################
# DIRECTORY CONFIRMED
###############################################################################

STORJ_DIR="$DIRECTORY_ARG"

VARIABLE_FILE="${STORJ_DIR}/${VARIABLE_FILE_NAME}"
LAUNCHER_FILE="${STORJ_DIR}/${LAUNCHER_FILE_NAME}"

echo
echo -e "${WHITE}    Storj directory:${RESET}"
echo "        $STORJ_DIR"
echo
echo "    Variables:"
echo "        $VARIABLE_FILE"
echo
echo "    Launcher:"
echo "        $LAUNCHER_FILE"
echo

###############################################################################
# GATE 6 - FILE CHECK
###############################################################################

gate "VALIDATING DISCOVERED FILES"

[[ -f "$VARIABLE_FILE" ]] ||
    abort "standard-variables.sh does not exist."

[[ -f "$LAUNCHER_FILE" ]] ||
    abort "standard-02-2025.sh does not exist."

[[ -r "$VARIABLE_FILE" ]] ||
    abort "standard-variables.sh is not readable."

[[ -w "$VARIABLE_FILE" ]] ||
    abort "standard-variables.sh is not writable."

[[ -r "$LAUNCHER_FILE" ]] ||
    abort "standard-02-2025.sh is not readable."

ok "Both files are accessible."

###############################################################################
# GATE 8 - EXACT Wallet= CHECK
###############################################################################

gate "LOCATING EXACT 'Wallet=' VARIABLE"

echo "IMPORTANT:"
echo
echo "    Wallet=    <-- THIS is the variable we will replace"
echo "    WALLET=    <-- THIS will be ignored"
echo
echo "The search is case-sensitive."
echo

###############################################################################
# Show every Wallet-like variable for debugging
###############################################################################

echo "All wallet-related variables currently present:"
echo

grep -nE '^[[:space:]]*(export[[:space:]]+)?[Ww][Aa][Ll][Ll][Ee][Tt][[:space:]]*=' \
    "$VARIABLE_FILE" || true

echo

###############################################################################
# EXACT CASE-SENSITIVE SEARCH
###############################################################################

# Match:
#
# Wallet=
# Wallet =
# Wallet = "..."
# export Wallet=
#
# But NOT:
#
# WALLET=
# wallet=
# WaLlEt=
#
WALLET_MATCHES=$(
    grep -nE '^[[:space:]]*(export[[:space:]]+)?Wallet[[:space:]]*=' \
        "$VARIABLE_FILE" || true
)

WALLET_COUNT=$(
    printf '%s\n' "$WALLET_MATCHES" |
    sed '/^[[:space:]]*$/d' |
    wc -l
)

echo "Exact capitalised Wallet= matches:"
echo

if [[ "$WALLET_COUNT" -eq 0 ]]; then

    fail "No exact 'Wallet=' variable was found."
    echo
    echo "The script WILL NOT create one."
    echo
    abort "Required existing Wallet= variable is missing."

fi

if [[ "$WALLET_COUNT" -gt 1 ]]; then

    fail "Multiple exact 'Wallet=' variables were found."
    echo
    echo "$WALLET_MATCHES"
    echo
    abort "Refusing to modify multiple Wallet variables."

fi

ok "Exactly ONE existing Wallet= variable was found."

echo
echo "$WALLET_MATCHES"
echo

###############################################################################
# EXTRACT CURRENT VALUE
###############################################################################

CURRENT_WALLET=$(
    printf '%s\n' "$WALLET_MATCHES" |
    sed -E \
        's/^[0-9]+:[[:space:]]*//' |
    sed -E \
        's/^[[:space:]]*(export[[:space:]]+)?Wallet[[:space:]]*=[[:space:]]*//' |
    sed -E \
        's/^["'\'']//; s/["'\'']$//'
)

echo
echo "Current Wallet value (from $VARIABLE_FILE_NAME):"
echo
echo "    $CURRENT_WALLET"
echo

###############################################################################
# GATE 9 - DISPLAY PROPOSED CHANGE
###############################################################################

gate "PROPOSED WALLET CHANGE"

echo -e "${RED}CURRENT:${RESET}"
echo
echo "    Wallet=$CURRENT_WALLET"
echo

echo -e "${GREEN}NEW:${RESET}"
echo
echo "    Wallet=$NEW_WALLET"
echo

echo "Only the existing capitalised Wallet= line will be changed."
echo
echo "WALLET= will NOT be changed."
echo "No new Wallet= variable will be created."
echo

###############################################################################
# GATE 10 - CREATE BACKUP DIRECTORY
###############################################################################

gate "PREPARING BACKUP"

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

BACKUP_DIR="${STORJ_DIR}/wallet-change-backup-${TIMESTAMP}"

echo "Backup directory:"
echo
echo "    $BACKUP_DIR"
echo

if [[ -e "$BACKUP_DIR" ]]; then
    abort "Backup directory already exists. Refusing to overwrite."
fi

mkdir -p "$BACKUP_DIR" ||
    abort "Could not create backup directory."

ok "Backup directory created."

###############################################################################
# SAVE DOCKER CONFIG
###############################################################################

docker inspect "$CONTAINER_ID" \
    > "$BACKUP_DIR/container-inspect.json" ||
    abort "Could not save Docker inspection."

cp -a "$VARIABLE_FILE" \
    "$BACKUP_DIR/standard-variables.sh.before" ||
    abort "Could not back up standard-variables.sh."

cp -a "$LAUNCHER_FILE" \
    "$BACKUP_DIR/standard-02-2025.sh.before" ||
    abort "Could not back up standard-02-2025.sh."

ok "Original configuration and scripts backed up."

###############################################################################
# GATE 11 - FINAL STOP CONFIRMATION
###############################################################################

gate "FINAL GATE BEFORE STOPPING CONTAINER"

echo -e "${WHITE}The following container is about to be stopped:${RESET}"
echo
echo "    Name : $CONTAINER_NAME"
echo "    ID   : $CONTAINER_ID"
echo
echo "The following file will then be modified:"
echo
echo "    $VARIABLE_FILE"
echo
echo "Only:"
echo
echo "    Wallet="
echo
echo "will be replaced."
echo
echo "The file will NOT be changed if Wallet= cannot be found exactly."
echo

read -r -p "Type STOP-AND-CHANGE to continue: " STOP_CONFIRM

if [[ "$STOP_CONFIRM" != "STOP-AND-CHANGE" ]]; then
    abort "Confirmation not received. Container remains running."
fi

###############################################################################
# STOP CONTAINER
###############################################################################

gate "STOPPING CURRENT STORJ CONTAINER"

echo "Executing:"
echo
echo "    docker stop $CONTAINER_ID"
echo

if ! docker stop "$CONTAINER_ID"; then
    abort "docker stop failed."
fi

ok "Docker stop command completed."

sleep 2

###############################################################################
# VERIFY STOP
###############################################################################

gate "VERIFYING CONTAINER HAS STOPPED"

POST_STOP_STATUS=$(
    docker inspect \
        --format '{{.State.Status}}' \
        "$CONTAINER_ID" 2>/dev/null ||
    echo "missing"
)

echo "Current state:"
echo
echo "    $POST_STOP_STATUS"
echo

if [[ "$POST_STOP_STATUS" != "exited" ]]; then
    abort "Container did not reach the expected exited state."
fi

ok "Container confirmed stopped."

###############################################################################
# GATE 12 - MODIFY EXISTING Wallet=
###############################################################################

gate "REPLACING EXISTING 'Wallet=' VALUE"

echo "Original line:"
echo

grep -nE '^[[:space:]]*(export[[:space:]]+)?Wallet[[:space:]]*=' \
    "$VARIABLE_FILE"

echo

###############################################################################
# Create temporary modified file
###############################################################################

TEMP_FILE=$(mktemp)

if ! awk -v new_wallet="$NEW_WALLET" '
{
    if ($0 ~ /^[[:space:]]*(export[[:space:]]+)?Wallet[[:space:]]*=/) {

        # Preserve indentation.
        match($0, /^[[:space:]]*/)
        indent = substr($0, RSTART, RLENGTH)

        # Preserve "export" if it already exists.
        if ($0 ~ /^[[:space:]]*export[[:space:]]+Wallet[[:space:]]*=/) {
            print indent "export Wallet=\"" new_wallet "\""
        }
        else {
            print indent "Wallet=\"" new_wallet "\""
        }

        changed++
    }
    else {
        print
    }
}
END {
    # EXACTLY ONE existing Wallet= must have been replaced.
    if (changed != 1) {
        exit 20
    }
}
' "$VARIABLE_FILE" > "$TEMP_FILE"; then

    rm -f "$TEMP_FILE"

    abort "Wallet replacement failed. Original file was NOT overwritten."
fi

###############################################################################
# GATE 13 - VERIFY TEMP FILE
###############################################################################

gate "VERIFYING PROPOSED FILE BEFORE COMMIT"

echo "Existing capitalised Wallet= lines in proposed file:"
echo

grep -nE '^[[:space:]]*(export[[:space:]]+)?Wallet[[:space:]]*=' \
    "$TEMP_FILE" || true

echo
echo "Uppercase WALLET= lines in proposed file:"
echo

grep -nE '^[[:space:]]*(export[[:space:]]+)?WALLET[[:space:]]*=' \
    "$TEMP_FILE" || true

echo

###############################################################################
# Count exact Wallet=
###############################################################################

PROPOSED_WALLET_COUNT=$(
    grep -Ec \
        '^[[:space:]]*(export[[:space:]]+)?Wallet[[:space:]]*=' \
        "$TEMP_FILE"
)

if [[ "$PROPOSED_WALLET_COUNT" -ne 1 ]]; then

    rm -f "$TEMP_FILE"

    abort "Proposed file does not contain exactly one Wallet= variable."
fi

###############################################################################
# Extract proposed value
###############################################################################

PROPOSED_WALLET=$(
    grep -E \
        '^[[:space:]]*(export[[:space:]]+)?Wallet[[:space:]]*=' \
        "$TEMP_FILE" |
    sed -E \
        's/^[[:space:]]*(export[[:space:]]+)?Wallet[[:space:]]*=[[:space:]]*//' |
    sed -E \
        's/^["'\'']//; s/["'\'']$//'
)

echo "Proposed Wallet value:"
echo
echo "    $PROPOSED_WALLET"
echo

if [[ "$PROPOSED_WALLET" != "$NEW_WALLET" ]]; then

    rm -f "$TEMP_FILE"

    abort "Proposed Wallet does not match NEW_WALLET."
fi

ok "Proposed Wallet value is correct."

###############################################################################
# SHELL SYNTAX CHECK
###############################################################################

gate "SHELL SYNTAX CHECK"

if bash -n "$TEMP_FILE"; then
    ok "Modified file passes bash syntax validation."
else

    rm -f "$TEMP_FILE"

    abort "Modified standard-variables.sh failed bash syntax validation."
fi

###############################################################################
# SHOW DIFF
###############################################################################

gate "EXACT CHANGE TO BE COMMITTED"

echo "Diff:"
echo

diff -u \
    "$VARIABLE_FILE" \
    "$TEMP_FILE" || true

echo

###############################################################################
# GATE 14 - COMMIT
###############################################################################

gate "FINAL FILE COMMIT GATE"

echo "The original file has already been backed up:"
echo
echo "    $BACKUP_DIR/standard-variables.sh.before"
echo
echo "The temporary file has passed:"
echo
echo "    Wallet= count check"
echo "    Wallet value check"
echo "    Bash syntax check"
echo
echo "The ONLY intended variable change is:"
echo
echo "    Wallet=$CURRENT_WALLET"
echo "        ->"
echo "    Wallet=$NEW_WALLET"
echo

read -r -p "Type COMMIT-WALLET to write the change: " COMMIT_CONFIRM

if [[ "$COMMIT_CONFIRM" != "COMMIT-WALLET" ]]; then

    rm -f "$TEMP_FILE"

    warn "Wallet change cancelled."
    warn "Container remains stopped."

    echo
    echo "Backup:"
    echo "    $BACKUP_DIR"
    echo

    exit 0
fi

###############################################################################
# COMMIT
###############################################################################

if ! cp -a "$TEMP_FILE" "$VARIABLE_FILE"; then

    rm -f "$TEMP_FILE"

    fail "Could not commit modified file."

    warn "Attempting automatic restoration from backup..."

    cp -a \
        "$BACKUP_DIR/standard-variables.sh.before" \
        "$VARIABLE_FILE" ||
        abort "CRITICAL: Automatic restoration failed."

    ok "Original file restored."

    abort "Wallet change was not committed."
fi

rm -f "$TEMP_FILE"

ok "Modified standard-variables.sh committed."

###############################################################################
# GATE 15 - VERIFY ACTUAL FILE
###############################################################################

gate "VERIFYING ACTUAL COMMITTED FILE"

echo "Wallet lines:"
echo

grep -nE '^[[:space:]]*(export[[:space:]]+)?Wallet[[:space:]]*=' \
    "$VARIABLE_FILE"

echo

ACTUAL_WALLET=$(
    grep -E \
        '^[[:space:]]*(export[[:space:]]+)?Wallet[[:space:]]*=' \
        "$VARIABLE_FILE" |
    sed -E \
        's/^[[:space:]]*(export[[:space:]]+)?Wallet[[:space:]]*=[[:space:]]*//' |
    sed -E \
        's/^["'\'']//; s/["'\'']$//'
)

echo "Actual Wallet:"
echo
echo "    $ACTUAL_WALLET"
echo

if [[ "$ACTUAL_WALLET" != "$NEW_WALLET" ]]; then

    fail "Actual Wallet does NOT match requested Wallet."

    warn "Restoring original file..."

    cp -a \
        "$BACKUP_DIR/standard-variables.sh.before" \
        "$VARIABLE_FILE" ||
        abort "CRITICAL: Could not restore original file."

    ok "Original file restored."

    abort "Wallet verification failed."
fi

ok "Actual Wallet matches the requested new Wallet."

###############################################################################
# VERIFY WALLET VARIABLE WAS NOT DUPLICATED
###############################################################################

gate "VERIFYING NO EXTRA 'Wallet=' WAS CREATED"

FINAL_WALLET_COUNT=$(
    grep -Ec \
        '^[[:space:]]*(export[[:space:]]+)?Wallet[[:space:]]*=' \
        "$VARIABLE_FILE"
)

echo "Exact Wallet= count:"
echo
echo "    $FINAL_WALLET_COUNT"
echo

if [[ "$FINAL_WALLET_COUNT" -ne 1 ]]; then
    abort "Unexpected Wallet= count after modification."
fi

ok "Exactly one capitalised Wallet= exists."

###############################################################################
# VERIFY UPPERCASE WALLET WAS NOT ALTERED
###############################################################################

gate "VERIFYING 'WALLET=' WAS NOT TARGETED"

echo "Uppercase WALLET= entries:"
echo

grep -nE \
    '^[[:space:]]*(export[[:space:]]+)?WALLET[[:space:]]*=' \
    "$VARIABLE_FILE" || true

echo
ok "Uppercase WALLET= was not targeted by the replacement."

###############################################################################
# GATE 16 - FINAL LAUNCH PREPARATION
###############################################################################

gate "PREPARING TO LAUNCH STORJ"

echo "Current working directory:"
pwd

echo
echo "Changing to:"
echo
echo "    $STORJ_DIR"
echo

cd "$STORJ_DIR" ||
    abort "Could not change to Storj directory."

ok "Working directory changed."

echo
echo "Current directory is now:"
pwd

echo
echo "Launcher:"
echo "    ./$LAUNCHER_FILE_NAME"
echo

###############################################################################
# VERIFY LAUNCHER
###############################################################################

if [[ ! -f "./$LAUNCHER_FILE_NAME" ]]; then
    abort "Launcher is not present in current directory."
fi

if [[ ! -r "./$LAUNCHER_FILE_NAME" ]]; then
    abort "Launcher is not readable."
fi

###############################################################################
# SHOW LAUNCHER REFERENCES
###############################################################################

echo
echo "Launcher references:"
echo

grep -nEi \
    'standard-variables\.sh|source[[:space:]]|^[[:space:]]*\.' \
    "./$LAUNCHER_FILE_NAME" || true

echo

###############################################################################
# FINAL LAUNCH GATE
###############################################################################

gate "FINAL LAUNCH GATE"

echo -e "${WHITE}Everything required has now passed.${RESET}"
echo
echo "Container stopped:"
echo "    $CONTAINER_NAME"
echo
echo "Correct directory:"
echo "    $STORJ_DIR"
echo
echo "Updated file:"
echo "    $VARIABLE_FILE"
echo
echo "New Wallet:"
echo "    $NEW_WALLET"
echo
echo "Launcher:"
echo "    $LAUNCHER_FILE"
echo
echo "Backup:"
echo "    $BACKUP_DIR"
echo

read -r -p "Type LAUNCH-STORJ to execute the launcher: " LAUNCH_CONFIRM

if [[ "$LAUNCH_CONFIRM" != "LAUNCH-STORJ" ]]; then

    warn "Launch cancelled."
    warn "Container remains stopped."

    echo
    echo "To restore the original Wallet:"
    echo
    echo "    cp -a \"$BACKUP_DIR/standard-variables.sh.before\" \"$VARIABLE_FILE\""
    echo

    exit 0
fi

###############################################################################
# LAUNCH
###############################################################################

gate "EXECUTING STANDARD-02-2025.SH"

echo "Working directory:"
pwd

echo
echo "Executing:"
echo
echo "    bash ./$LAUNCHER_FILE_NAME"
echo

bash "./$LAUNCHER_FILE_NAME"

LAUNCH_EXIT=$?

echo
echo "Launcher exit code:"
echo "    $LAUNCH_EXIT"
echo

if [[ "$LAUNCH_EXIT" -eq 0 ]]; then
    ok "Launcher returned exit code 0."
else
    warn "Launcher returned exit code $LAUNCH_EXIT."
fi

###############################################################################
# WAIT FOR CONTAINER
###############################################################################

gate "WAITING FOR STORJ CONTAINER TO RETURN"

echo "Waiting up to $START_TIMEOUT seconds..."
echo

FOUND_RUNNING=0

for ((i=1; i<=START_TIMEOUT; i++)); do

    sleep 1

    CURRENT_ID=$(
        docker ps \
            --filter "name=^/${CONTAINER_NAME}$" \
            --format '{{.ID}}' |
        head -n1
    )

    if [[ -n "$CURRENT_ID" ]]; then

        CURRENT_STATUS=$(
            docker inspect \
                --format '{{.State.Status}}' \
                "$CURRENT_ID" 2>/dev/null ||
            echo "unknown"
        )

        printf "\r    [%02d/%02d] Container status: %-12s" \
            "$i" \
            "$START_TIMEOUT" \
            "$CURRENT_STATUS"

        if [[ "$CURRENT_STATUS" == "running" ]]; then
            FOUND_RUNNING=1
            echo
            break
        fi

    else

        printf "\r    [%02d/%02d] Container status: %-12s" \
            "$i" \
            "$START_TIMEOUT" \
            "not-running"

    fi

done

echo
echo

###############################################################################
# FINAL VERIFICATION
###############################################################################

gate "FINAL CONTAINER VERIFICATION"

FINAL_ID=$(
    docker ps \
        --filter "name=^/${CONTAINER_NAME}$" \
        --format '{{.ID}}' |
    head -n1
)

if [[ -z "$FINAL_ID" ]]; then

    fail "Storj container is NOT running."

    echo
    echo "Docker status:"
    docker ps -a \
        --filter "name=^/${CONTAINER_NAME}$" \
        --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}'

    echo
    echo "Recent container logs:"
    echo

    docker logs \
        --tail 100 \
        "$CONTAINER_NAME" \
        2>&1 || true

    echo
    warn "The Wallet file was successfully modified."
    warn "The container, however, did not return to running state."

    echo
    echo "Backup:"
    echo "    $BACKUP_DIR"

    exit 2
fi

FINAL_STATUS=$(
    docker inspect \
        --format '{{.State.Status}}' \
        "$FINAL_ID"
)

echo "Final container:"
echo
echo "    ID     : $FINAL_ID"
echo "    Name   : $CONTAINER_NAME"
echo "    Status : $FINAL_STATUS"
echo

if [[ "$FINAL_STATUS" != "running" ]]; then
    fail "Container exists but is not running."
    exit 2
fi

ok "Storj container is RUNNING."

###############################################################################
# FINAL DOCKER STATE
###############################################################################

gate "FINAL DOCKER STATE"

docker ps \
    --filter "name=^/${CONTAINER_NAME}$" \
    --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Names}}'

echo

###############################################################################
# FINAL SUMMARY
###############################################################################

echo
echo -e "${GREEN}======================================================================${RESET}"
echo -e "${GREEN}                    OPERATION COMPLETED${RESET}"
echo -e "${GREEN}======================================================================${RESET}"
echo
echo " Container       : $CONTAINER_NAME"
echo " Container ID    : $FINAL_ID"
echo " Status          : $FINAL_STATUS"
echo
echo " Storj directory : $STORJ_DIR"
echo
echo " Variables file  : $VARIABLE_FILE"
echo " Launcher        : $LAUNCHER_FILE"
echo
echo " Old Wallet      : $CURRENT_WALLET"
echo " New Wallet      : $NEW_WALLET"
echo
echo " Backup          : $BACKUP_DIR"
echo
echo " Launcher exit   : $LAUNCH_EXIT"
echo " Completed       : $(date)"
echo

if [[ "$FINAL_STATUS" == "running" ]]; then

    echo -e "${GREEN}----------------------------------------------------------------------${RESET}"
    echo -e "${GREEN}  SUCCESS: Wallet replaced and Storj container is running.${RESET}"
    echo -e "${GREEN}----------------------------------------------------------------------${RESET}"

else

    echo -e "${RED}----------------------------------------------------------------------${RESET}"
    echo -e "${RED}  WARNING: Storj container is not running.${RESET}"
    echo -e "${RED}----------------------------------------------------------------------${RESET}"

fi

echo
