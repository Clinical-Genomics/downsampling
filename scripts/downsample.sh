#!/bin/bash

set -euo pipefail   # -e: exit on error, -u: error on unset vars, -o pipefail: catch failures anywhere in a pipe

log() {
    >&2 echo "$*"
}

VERSION=2.0.0
log "VERSION $VERSION"

##################
# MATCH PATTERNS #
##################

FORWARD_PATTERN='*_R1_*.fastq.gz'
REVERSE_PATTERN='*_R2_*.fastq.gz'

#########
# USAGE #
#########

if [[ $# -lt 3 ]]; then
    echo "Usage:"
    echo "      $0 [-2] indir outdir readpairs [total readpairs]"
    echo ""
    echo "      with:"
    echo "      -2: To reduce memory footprint, do a double pass. Takes twice as long."
    echo "              indir: input dir, matched with:"
    echo "                     - forward: $FORWARD_PATTERN"
    echo "                     - reverse: $REVERSE_PATTERN"
    echo "              outdir: output dir (created if missing)"
    echo "              readpairs: number of read pairs to keep"
    echo "      total reads: for fractional/estimate mode. Not compatible with -2."
    exit 1
fi

##########
# params #
##########

DOUBLEPASS=
if [[ "$1" == '-2' ]]; then
    DOUBLEPASS='-2'
    shift
fi

INDIR=$1
OUTDIR=$2
READS=$3
TOTALREADS=${4:-}

if [[ -n "$DOUBLEPASS" && -n "$TOTALREADS" ]]; then
    log "ERROR: -2 and [total readpairs] fractional mode cannot be combined."
    exit 1
fi

mkdir -p "$OUTDIR"

##################
# find input files #
##################

FORWARD_IN=$(ls -1 ${INDIR}/${FORWARD_PATTERN} 2>/dev/null | head -1) || true
if [[ -z "$FORWARD_IN" ]]; then
    log "ERROR: No forward strand files found matching $FORWARD_PATTERN in $INDIR"
    exit 1
fi

REVERSE_IN=$(ls -1 ${INDIR}/${REVERSE_PATTERN} 2>/dev/null | head -1) || true
if [[ -z "$REVERSE_IN" ]]; then
    log "ERROR: No reverse strand files found matching $REVERSE_PATTERN in $INDIR"
    exit 1
fi

FORWARD_OUTFILE=$(basename "$FORWARD_IN")
REVERSE_OUTFILE=$(basename "$REVERSE_IN")

log "Input files FORWARD:"
ls ${INDIR}/${FORWARD_PATTERN} >&2

log "Input files REVERSE:"
ls ${INDIR}/${REVERSE_PATTERN} >&2

# single seed shared by both mates so pairs stay in sync
SEED=$RANDOM

SAMPLESIZE=$READS
if [[ -n "$TOTALREADS" ]]; then
    FRACTION=$(bc -l <<< "$READS/$TOTALREADS")
    log "Switching to fractional mode: $FRACTION"
    SAMPLESIZE=$FRACTION
fi

SEQTK=/home/proj/production/bin/git/downsampling/seqtk/seqtk

########
# RUN! #
########

downsample() {
    local pattern=$1
    local outfile=$2
    log "Running: zcat ${INDIR}/${pattern} | seqtk sample -s $SEED $DOUBLEPASS $SAMPLESIZE | gzip -c > ${OUTDIR}/${outfile}"
    zcat ${INDIR}/${pattern} \
        | "$SEQTK" sample -s "$SEED" $DOUBLEPASS - "$SAMPLESIZE" \
        | gzip -c > "${OUTDIR}/${outfile}"
}

# Run forward and reverse in parallel background jobs, but ACTUALLY check both exit codes.
downsample "$FORWARD_PATTERN" "$FORWARD_OUTFILE" &
FWD_PID=$!

downsample "$REVERSE_PATTERN" "$REVERSE_OUTFILE" &
REV_PID=$!

# clean up children on ctrl+c / kill
trap 'kill "$FWD_PID" "$REV_PID" 2>/dev/null || true' INT TERM

FAIL=0
wait "$FWD_PID" || { log "ERROR: forward downsampling failed"; FAIL=1; }
wait "$REV_PID" || { log "ERROR: reverse downsampling failed"; FAIL=1; }

if [[ $FAIL -ne 0 ]]; then
    log "One or more downsampling jobs failed — output is incomplete/untrustworthy."
    exit 1
fi

##################
# sanity check    #
##################

for f in "${OUTDIR}/${FORWARD_OUTFILE}" "${OUTDIR}/${REVERSE_OUTFILE}"; do
    if ! gzip -t "$f" 2>/dev/null; then
        log "ERROR: $f failed gzip integrity check (truncated?)"
        exit 1
    fi
done

log "Done. Output written to $OUTDIR"
