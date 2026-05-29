#!/usr/bin/env bash
#
# encoding.sh - Check encoding issues in Anbennar EU4 mod files.
#
# Examples:
#   encoding.sh -t    # validate all .txt files (events, missions, decisions)
#   encoding.sh -l    # validate all localization files
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'



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
    declare -i NEUTRAL=0

    for f in "${files[@]}"; do
        TOTAL+=1
        local encoding
        encoding=$(file -b --mime-encoding "$f")

        if [[ "$encoding" == us-ascii ]]; then
            GOOD+=1
        elif [[ "$encoding" == iso-8859-1 ]]; then
            GOOD+=1
            NEUTRAL+=1
        elif [[ "$encoding" == unknown-8bit ]]; then
            echo -e "${YELLOW}{$f} encoding is unknown!${NC}"
            file -i "$f"
            NEUTRAL+=1
            GOOD+=1
        else
            echo -e "${RED}{$f} encoding is wrong! (found: $encoding)${NC}"
            file -i "$f"
            ERR+=1
        fi
    done

    echo ""
    echo -e "\n		${GREEN}${GOOD}${NC}/${TOTAL} ${GREEN}${label} files encoding validated.${NC}\n"
    if [[ $NEUTRAL -gt 0 ]]; then
        echo -e "		${YELLOW}${NEUTRAL}${NC}/${TOTAL} ${YELLOW}${label} files encoding are in european ascii or unknown.${NC}\n"
    fi
    if [[ $ERR -gt 0 ]]; then
        echo -e "\n		${RED}${ERR}${NC}/${TOTAL} ${RED}${label} files have a wrong encoding!${NC}\n"
        exit 1
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
    declare -i NEUTRAL=0

    for f in "${files[@]}"; do
        TOTAL+=1
        local encoding
        encoding=$(file -b --mime-encoding "$f")

        if has_bom "$f" && [[ "$encoding" == utf-8 ]]; then
            GOOD+=1
        elif has_bom "$f" && [[ "$encoding" == binary ]]; then
            echo -e "${YELLOW}{$f} has a BOM but 'file' reports binary - ignoring${NC}"
            NEUTRAL+=1
            GOOD+=1
        else
            echo -e "${RED}{$f} encoding is wrong! (found: $encoding)${NC}"
            file -i "$f"
            ERR+=1
        fi
    done

    echo ""
    echo -e "\n		${GREEN}${GOOD}${NC}/${TOTAL} ${GREEN}localization files encoding validated.${NC}\n"
    if [[ $NEUTRAL -gt 0 ]]; then
        echo -e "\n		${YELLOW}${NEUTRAL}${NC}/${TOTAL} ${YELLOW}files encoding reported as binary but have BOM.${NC}\n"
    fi
    if [[ $ERR -gt 0 ]]; then
        echo -e "\n		${RED}${ERR}${NC}/${TOTAL} ${RED}localization files have a wrong or unknown encoding!${NC}\n"
        exit 1
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
    echo "Usage: $0 [-t] [-l] [-i] [-h] [file...]"
    echo ""
    echo "Check encoding issues in Anbennar EU4 mod files."
    echo ""
    echo "Options:"
    echo -e "\t-t         Process .txt files (events, missions, decisions)"
    echo -e "\t-l         Process .yml files (localisation)"
    echo -e "\t-i         Check .txt files for broken indentation (bracket counting)"
    echo -e "\t-h         Show this help"
    echo ""
    echo "Notes:"
    echo -e "\t- Files with iso-8859-1 or unknown-8bit encoding are reported but considered OK"
    echo -e "\t- UTF-8 encoded .txt files are considered wrong (EU4 requires ASCII/latin-1)"
    echo -e "\t- .yml files must be UTF-8 with BOM"
    echo -e "\t- When specific file paths are provided after the flags, only those files are processed"
    echo -e "\t  (otherwise the default glob for the selected type is used)"
    echo ""
    echo "Examples:"
    echo "  $0 -t -l                       # validate all .txt and .yml files"
    echo "  $0 -t events/foo.txt           # validate only the given file"
    echo "  $0 -l localisation/*.yml       # validate specific localization files"
    exit 1
}

# -----------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------



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
        t) process_txt_files "text" "./events/*.txt ./missions/*.txt ./decisions/*.txt ./common/*/*.txt" "${remaining_files[@]}" ;;
        l) process_localization "${remaining_files[@]}" ;;
        i) process_indentation "${remaining_files[@]}" ;;
    esac
done
