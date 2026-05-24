#!/usr/bin/env bash
#
# encoding.sh - Check and fix encoding issues in Anbennar EU4 mod files.
#
# Default mode: validate encoding (check).
# Use --fix to apply fixes, --dry-run to preview without changes.
#
# Examples:
#   encoding.sh -t                     # validate all .txt files (events, missions, decisions)
#   encoding.sh -l                     # validate all localization files
#   encoding.sh --fix -t -l            # fix all .txt and .yml files
#   encoding.sh --fix --dry-run -t -l  # preview fixes
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

FIX_MODE=false
DRY_RUN=false

# -----------------------------------------------------------
# Helpers
# -----------------------------------------------------------

has_bom() { head -c3 "$1" | grep -q $'\xef\xbb\xbf'; }

# -----------------------------------------------------------
# TXT file processing (events, missions, decisions)
# -----------------------------------------------------------

process_txt_files() {
    local label="$1"
    local default_glob="$2"
    shift 2
    local -a files=("$@")
    if [ ${#files[@]} -eq 0 ]; then
        # shellcheck disable=SC2206
        files=($default_glob)
    fi

    echo "--------------------------------------------------------------------------------------------------------------------------------"
    declare -i TOTAL=0
    declare -i GOOD=0
    declare -i ERR=0

    if $FIX_MODE; then
        declare -i FIXED=0
    else
        declare -i NEUTRAL=0
    fi

    for f in "${files[@]}"; do
        TOTAL+=1
        local encoding
        encoding=$(file -b --mime-encoding "$f")

        if [[ "$encoding" == us-ascii ]]; then
            GOOD+=1
        elif [[ "$encoding" == iso-8859-1 ]]; then
            GOOD+=1
            if ! $FIX_MODE; then
                NEUTRAL+=1
            fi
        elif [[ "$encoding" == unknown-8bit ]]; then
            if ! $FIX_MODE; then
                echo -e "${YELLOW}{$f} encoding is unknown!${NC}"
                file -i "$f"
                NEUTRAL+=1
            fi
            GOOD+=1
        elif $FIX_MODE && [[ "$encoding" == utf-8 ]]; then
            echo -e "${RED}[FIX]${NC} $f (encoding: $encoding)"
            if $DRY_RUN; then
                FIXED+=1
                continue
            fi

            local tmpfile
            tmpfile=$(mktemp "${f}.XXXXXX")
            local err=0

            if iconv -f UTF-8 -t ASCII//TRANSLIT "$f" | cat > "$tmpfile" 2>/dev/null; then
                mv "$tmpfile" "$f"
                echo -e "${GREEN}[OK]${NC} Converted from UTF-8 to ASCII"
                FIXED+=1
            else
                echo -e "${YELLOW}[RETRY]${NC} Trying with //IGNORE..."
                if iconv -f UTF-8 -t ASCII//IGNORE "$f" | cat > "$tmpfile" 2>/dev/null; then
                    mv "$tmpfile" "$f"
                    echo -e "${GREEN}[OK]${NC} Converted from UTF-8 to ASCII (with IGNORE)"
                    FIXED+=1
                else
                    echo -e "${RED}[FAIL]${NC} Could not convert $f from UTF-8"
                    rm -f "$tmpfile"
                    err=1
                fi
            fi

            rm -f "$tmpfile"
            if [[ $err -ne 0 ]]; then
                ERR+=1
            fi
        else
            if $FIX_MODE; then
                echo -e "${RED}[FAIL]${NC} $f (encoding: $encoding)"
            else
                echo -e "${RED}{$f} encoding is wrong!${NC}"
                file -i "$f"
            fi
            ERR+=1
        fi
    done

    echo ""
    if $FIX_MODE; then
        if $DRY_RUN; then
            echo -e "		${YELLOW}${FIXED}${NC}/${TOTAL} ${YELLOW}${label} files would be fixed.${NC}"
        else
            echo -e "		${GREEN}${GOOD}${NC}/${TOTAL} ${GREEN}${label} files already correct.${NC}"
            echo -e "		${GREEN}${FIXED}${NC}/${TOTAL} ${GREEN}${label} files fixed.${NC}"
        fi
        echo ""
        if [[ $ERR -gt 0 ]]; then
            echo -e "		${RED}${ERR}${NC} ${RED}${label} files could not be fixed!${NC}\n"
        fi
        if [[ $FIXED -gt 0 ]]; then
            echo -e "\n${YELLOW}Please manually review the changed files for characters with broken encoding.${NC}"
            echo -e "${YELLOW}Run 'git diff' to see what changed.${NC}"
        fi
    else
        echo -e "\n		${GREEN}${GOOD}${NC}/${TOTAL} ${GREEN}${label} files encoding validated.${NC}\n"
        if [[ $NEUTRAL -gt 0 ]]; then
            echo -e "		${YELLOW}${NEUTRAL}${NC}/${TOTAL} ${YELLOW}${label} files encoding are in european ascii or unknown.${NC}\n"
        fi
        if [[ $ERR -gt 0 ]]; then
            echo -e "\n		${RED}${ERR}${NC}/${TOTAL} ${RED}${label} files have a wrong encoding!${NC}\n"
            exit 1
        fi
    fi
}

# -----------------------------------------------------------
# YML / localization file processing
# -----------------------------------------------------------

process_localization() {
    local -a files=("$@")
    if [ ${#files[@]} -eq 0 ]; then
        files=(./localisation/*.yml)
    fi

    echo "--------------------------------------------------------------------------------------------------------------------------------"
    declare -i TOTAL=0
    declare -i GOOD=0
    declare -i ERR=0

    if $FIX_MODE; then
        declare -i FIXED=0
    else
        declare -i NEUTRAL=0
    fi

    for f in "${files[@]}"; do
        TOTAL+=1
        local encoding
        encoding=$(file -b --mime-encoding "$f")

        if has_bom "$f" && [[ "$encoding" == utf-8 ]]; then
            GOOD+=1
        elif has_bom "$f" && [[ "$encoding" == binary ]]; then
            if $FIX_MODE; then
                echo -e "${YELLOW}[SKIP]${NC} $f (reported as binary but has BOM - content may need manual review)"
            else
                echo -e "${YELLOW}{$f} has a BOM but 'file' reports binary - ignoring${NC}"
                NEUTRAL+=1
            fi
            GOOD+=1
        else
            if $FIX_MODE; then
                echo -e "${RED}[FIX]${NC} $f (encoding: $encoding)"
                if $DRY_RUN; then
                    FIXED+=1
                    continue
                fi

                local tmpfile
                tmpfile=$(mktemp "${f}.XXXXXX")
                local err=0

                local src_enc="$encoding"
                if [[ "$encoding" == unknown-8bit ]]; then
                    src_enc="CP1252"
                fi

                if iconv -f "$src_enc" -t UTF-8 "$f" | cat > "$tmpfile" 2>/dev/null; then
                    printf '\xef\xbb\xbf' | cat - "$tmpfile" > "$f"
                    echo -e "${GREEN}[OK]${NC} Converted from $src_enc to UTF-8 with BOM"
                    FIXED+=1
                else
                    echo -e "${RED}[FAIL]${NC} Could not convert $f from $src_enc"
                    rm -f "$tmpfile"
                    err=1
                fi

                rm -f "$tmpfile"
                if [[ $err -ne 0 ]]; then
                    ERR+=1
                fi
            else
                echo -e "${RED}{$f} encoding is wrong!${NC}"
                file -i "$f"
                ERR+=1
            fi
        fi
    done

    echo ""
    if $FIX_MODE; then
        if $DRY_RUN; then
            echo -e "		${YELLOW}${FIXED}${NC}/${TOTAL} ${YELLOW}localization files would be fixed.${NC}"
        else
            echo -e "		${GREEN}${GOOD}${NC}/${TOTAL} ${GREEN}localization files already correct.${NC}"
            echo -e "		${GREEN}${FIXED}${NC}/${TOTAL} ${GREEN}localization files fixed.${NC}"
        fi
        echo ""
        if [[ $ERR -gt 0 ]]; then
            echo -e "		${RED}${ERR}${NC} ${RED}localization files could not be fixed!${NC}\n"
        fi
        if [[ $FIXED -gt 0 ]]; then
            echo -e "\n${YELLOW}Please manually review the changed files for characters with broken encoding.${NC}"
            echo -e "${YELLOW}Run 'git diff' to see what changed.${NC}"
        fi
    else
        echo -e "\n		${GREEN}${GOOD}${NC}/${TOTAL} ${GREEN}localization files encoding validated.${NC}\n"
        if [[ $NEUTRAL -gt 0 ]]; then
            echo -e "\n		${YELLOW}${NEUTRAL}${NC}/${TOTAL} ${YELLOW}files encoding reported as binary but have BOM.${NC}\n"
        fi
        if [[ $ERR -gt 0 ]]; then
            echo -e "\n		${RED}${ERR}${NC}/${TOTAL} ${RED}localization files have a wrong or unknown encoding!${NC}\n"
            exit 1
        fi
    fi
}

# -----------------------------------------------------------
# Indentation (bracket balance) check
# -----------------------------------------------------------

process_indentation() {
    local -a files=("$@")
    if [ ${#files[@]} -eq 0 ]; then
        files=(./*/*.txt ./common/*/*.txt)
    fi

    echo "--------------------------------------------------------------------------------------------------------------------------------"
    declare -i GOOD=0
    declare -i BAD=0
    declare -i TOTAL=0

    for f in "${files[@]}"; do
        LEFT=$(LC_ALL=C grep -o '^[^#]*' "$f" | grep -o '{' | wc -l)
        RIGHT=$(LC_ALL=C grep -o '^[^#]*' "$f" | grep -o '}' | wc -l)
        TOTAL+=1

        if [ $LEFT != $RIGHT ]; then
            echo "${f}"
            echo -e "${BLUE}${LEFT}${NC}/${CYAN}${RIGHT}${NC} ${RED}Broken syntax, inequal number of brackets.${NC}\n"
            BAD+=1
        else
            GOOD+=1
        fi
    done

    echo -e "\n		${GREEN}${GOOD}${NC}/${TOTAL} ${GREEN} files syntax validated.${NC}\n"
    if [[ $BAD -gt 0 ]]; then
        echo -e "\n		${RED}${BAD}${NC}/${TOTAL} ${RED} files syntax are wrong!${NC}\n"
        exit 1
    fi
}

# -----------------------------------------------------------
# Help
# -----------------------------------------------------------

help_function() {
    echo ""
    echo "Usage: $0 [--fix] [--dry-run] [-t] [-l] [-i] [-h] [file...]"
    echo ""
    echo "Check or fix encoding issues in Anbennar EU4 mod files."
    echo "Default mode is validation (check). Use --fix to apply fixes."
    echo ""
    echo "Options:"
    echo -e "\t--fix      Enable fix mode (default is check/validate only)"
    echo -e "\t--dry-run  Only show what would be fixed without making changes (fix mode only)"
    echo -e "\t-t         Process .txt files (events, missions, decisions)"
    echo -e "\t-l         Process .yml files (localisation)"
    echo -e "\t-i         Check .txt files for broken indentation (bracket counting)"
    echo -e "\t-h         Show this help"
    echo ""
    echo "Fixes applied (when --fix is used):"
    echo -e "\t- .yml files: Convert to UTF-8 with BOM (required by EU4 for localization)"
    echo -e "\t- .txt files: Convert from UTF-8 to ASCII (smart quotes, ellipsis become plain ASCII)"
    echo ""
    echo "Notes:"
    echo -e "\t- Files with iso-8859-1 or unknown-8bit encoding are left alone (they work in EU4)"
    echo -e "\t- Only UTF-8 encoded .txt files are considered broken and get fixed"
    echo -e "\t- When specific file paths are provided after the flags, only those files are processed"
    echo -e "\t  (otherwise the default glob for the selected type is used)"
    echo ""
    echo "Examples:"
    echo "  $0 -t -l                       # validate all .txt and .yml files"
    echo "  $0 --fix -t -l                 # fix all .txt and .yml files"
    echo "  $0 -t events/foo.txt           # validate only the given file"
    echo "  $0 --fix -l localisation/*.yml # fix specific localization files"
    echo "  $0 --fix --dry-run -t -l       # preview what would be fixed"
    exit 1
}

# -----------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------

# Extract --fix and --dry-run from anywhere in the argument list
declare -a filtered_args=()
for arg in "$@"; do
    case "$arg" in
        --fix) FIX_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        *) filtered_args+=("$arg") ;;
    esac
done
set -- "${filtered_args[@]}"

declare -a modes=()

while getopts "tlidh" opt; do
    case "$opt" in
        t) modes+=("t") ;;
        l) modes+=("l") ;;
        i) modes+=("i") ;;
        h|:) help_function ;;
        \?) help_function ;;
    esac
done

shift $((OPTIND-1))
declare -a remaining_files=("$@")

if [ ${#modes[@]} -eq 0 ]; then
    modes=("t" "l" "i")
fi

# -----------------------------------------------------------
# Dispatch
# -----------------------------------------------------------

for mode in "${modes[@]}"; do
    case "$mode" in
        t) process_txt_files "text" "./events/*.txt ./missions/*.txt ./decisions/*.txt" "${remaining_files[@]}" ;;
        l) process_localization "${remaining_files[@]}" ;;
        i) process_indentation "${remaining_files[@]}" ;;
    esac
done
