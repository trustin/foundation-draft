#!/bin/bash -x

# Docker image for pandoc
if [[ -z "${PANDOCK}" ]]; then
    PANDOCK=ebullient/pandoc-emoji:3.1
fi
# Git commit information (SHA, date, repo url)
if [[ -z "${GIT_COMMIT}" ]]; then
    GIT_COMMIT=$(git rev-parse HEAD)
fi
SHA_RANGE="${GIT_COMMIT}"^.."${GIT_COMMIT}"
FOOTER=$(git --no-pager log --date=short --pretty="format:%ad ✧ commit %h%n" "${SHA_RANGE}")
MARK=$(git --no-pager log --date=short --pretty="format:%ad-%h%n" "${SHA_RANGE}")
URL=$(gh repo view --json url --jq '.url')/

# Docker command and arguments
ARGS="--rm -e TERM -e HOME=/data -u $(id -u):$(id -g) -v $(pwd):/data -w /data"
if [[ "$OSTYPE" == "darwin"* ]]; then
    ARGS="$ARGS --platform linux/amd64"
fi
DRY_RUN=${IS_PR:-false}
if [[ "${DRY_RUN}" != "false" ]]; then
    DOCKER="echo docker"
elif [[ -z "${DOCKER}" ]]; then
    DOCKER=docker
fi

TO_CMD=${1:-nope}
# Invoke command in the pandock container with common docker arguments
if [[ "${TO_CMD}" == "sh" ]]; then
    ${DOCKER} run ${ARGS} --entrypoint="" "${PANDOCK}" "$@"
    exit 0
fi
# Invoke pandoc with common docker arguments
if [[ "${TO_CMD}" != "nope" ]]; then
    ${DOCKER} run ${ARGS} "${PANDOCK}" "$@"
    exit 0
fi

# Convert markdown to PDF with an appended changelog
function to_pdf_with_changes() {
    local tmpout=output/tmp/${1}
    mkdir -p "${tmpout}"
    rm -f "${tmpout}"/*
    shift
    local changes=${1}
    shift
    local changelog=${1}
    shift
    local pdfout=output/public/${1}
    shift
    rm -f "${pdfout}"

    changelog "${changes}" "${changelog}"
    to_pdf --pdf-engine-opt=-output-dir="${tmpout}" \
        --pdf-engine-opt=-outdir="${tmpout}" \
        -o "${pdfout}" \
        "$@" "${changelog}"
}

# Convert markdown to PDF
function to_pdf() {
    ${DOCKER} run ${ARGS} \
        "${PANDOCK}" \
        -H ./.pandoc/header.tex \
        -A ./.pandoc/afterBody.tex \
        -d ./.pandoc/bylaws.yaml \
        -M date-meta:"$(date +%B\ %d,\ %Y)" \
        -V footer-left:"${FOOTER}" \
        -V github:"${URL}blob/${GIT_COMMIT}/" \
        "$@"
}

# Generate changelog from git log
function changelog() {
    echo "# Changelog
" > "${2}"
    git --no-pager log --reverse --date=short \
        --pretty=format:"- \`%ad\` ∙ [\`%h\`](${URL}commit/%H) ∙ %s" \
        origin "${GIT_COMMIT}" \
        -- "${1}" >> "${2}"
    echo "" >> "${2}"
}

mkdir -p output/tmp
mkdir -p output/public

## BYLAWS

# Sorted order of files for Bylaws
BYLAWS=(./bylaws/purpose.md
./bylaws/cf-membership.md
./bylaws/cf-council.md
./bylaws/cf-advisory-board.md
./bylaws/decision-making.md
./bylaws/notice-records.md
./bylaws/liability-indemnification.md
./bylaws/amendments.md
)

# Verify that bylaws files exist
for x in "${BYLAWS[@]}"; do
    if [[ ! -f ${x} ]]; then
        echo "No file found at ${x}"
        exit 1
    fi
done

# Convert bylaws to PDF
to_pdf_with_changes \
    bylaws \
    ./bylaws \
    output/tmp/bylaws-changelog.md \
    "cf-bylaws-${MARK}.pdf" \
    -M title:"Commonhaus Foundation Bylaws" \
    "${BYLAWS[@]}"

## POLICIES

# Convert individual policy to PDF
function to_policy_pdf() {
    if [[ ! -f "./policies/${1}.md" ]]; then
        echo "No policy found at ./policies/${1}.md"
        exit 1
    fi
    to_pdf_with_changes \
        "${1}" \
        "./policies/${1}.md" \
        "output/tmp/${1}-changelog.md" \
        "${1}-${MARK}.pdf" \
        -M title:"Commonhaus Foundation ${2} Policy" \
        "./policies/${1}.md"
}

# Convert all policies to PDF
to_policy_pdf code-of-conduct "Code of Conduct"
to_policy_pdf conflict-of-interest "Conflict of Interest"
to_policy_pdf dissolution-policy "Dissolution"
to_policy_pdf ip-policy "Intellectual Property"
to_policy_pdf succession-plan "Continuity and Administrative Access"
to_policy_pdf trademark-policy "Trademark"

# TODO: to_policy_pdf privacy "Privacy"
