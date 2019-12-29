#!/bin/bash

# exit on errr
set -e

log() {
    >&2 echo $*
}

VERSION=1.5.0
log VERSION $VERSION

##################
# MATCH PATTERNS #
##################

# Change the file matching pattern here if needed

FORWARD_PATTERN='*_R1_*.fastq.gz'
REVERSE_PATTERN='*_R2_*.fastq.gz'

#########
# USAGE #
#########

if [[ $# < 3 ]]; then
    echo "Usage:"
    echo "	$0 [-2] indir outdir readpairs [total readpairs]"
    echo ""
    echo "	with:"
    echo "      -2: To reduce memory footprint, do a doube pass. Takes twice as long."
    echo "		indir: The input directory. The script will expect forward and reverse"
    echo "		       strand files found with a matching pattern."
    echo "		       - forward match pattern: $FORWARD_PATTERN"
    echo "		       - reverse match pattern: $REVERSE_PATTERN"
    echo "		outdir: The output directory. Will be created if it does not exist."
    echo "		       One output file per strand will be created in this directory."
    echo "		       The output file name will be the first file name in the input"
    echo "		       directory matched with above mentioned patterns."
    echo "		readpairs: The amount of read pairs to keep."
    echo "      total reads: To reduce memory footprint, will produce an estimate amount"
    echo "                   of read pairs to keep. Does NOT work with the -2 option"
    echo "                   Only requires two cores."

    exit 1
fi

##########
# params #
##########

DOUBLEPASS=$1
if [[ $DOUBLEPASS == '-2' ]]; then 
    shift
else
    DOUBLEPASS=
fi

INDIR=$1
OUTDIR=$2
READS=$3
TOTALREADS=$4

[[ ! -e $OUTDIR ]] && mkdir $OUTDIR

########
# RUN! #
########

# get first file name - forward
FORWARD_OUTFILE=`ls -1 ${INDIR}/${FORWARD_PATTERN} | head -1`
if [[ ! -e $FORWARD_OUTFILE ]]; then
    error 'No forward strands found!'
    exit 1
fi
FORWARD_OUTFILE=`basename $FORWARD_OUTFILE`

# get first file name - reverse
REVERSE_OUTFILE=`ls -1 ${INDIR}/${REVERSE_PATTERN} | head -1`
if [[ ! -e $REVERSE_OUTFILE ]]; then
    error 'No reverse strands found!'
    exit 1
fi
REVERSE_OUTFILE=`basename $REVERSE_OUTFILE`

# get a random number (range 0-32k)
SEED=$RANDOM

log 'Input files FORWARD:'
ls ${INDIR}/${FORWARD_PATTERN}

log 'Input files REVERSE:'
ls ${INDIR}/${REVERSE_PATTERN}

SAMPLESIZE=$READS
if [[ ! -z $TOTALREADS ]]; then
    FRACTION=$( bc -l <<< "$READS/$TOTALREADS" )
    log "Switching to fractional mode: ${FRACTION}"
    SAMPLESIZE=$FRACTION
fi

log 'Running:'

# create a temp file to store the PID of seqtk
PIDFILE=`mktemp`

# create forward downsample file -- and put it in the background
COMMAND1="seqtk sample -s $SEED $DOUBLEPASS"
COMMAND2="gzip --to-stdout"
log "$COMMAND1 <(zcat ${INDIR}/${FORWARD_PATTERN}) $SAMPLESIZE | $COMMAND2 > ${OUTDIR}/${FORWARD_OUTFILE} &"
( echo $BASHPID > $PIDFILE; exec $COMMAND1 <(zcat ${INDIR}/${FORWARD_PATTERN}) $SAMPLESIZE ) | $COMMAND2 > ${OUTDIR}/${FORWARD_OUTFILE} &

# remove the background seqtk on ctrl+c
trap "kill `cat $PIDFILE`; rm $PIDFILE" INT KILL

# do one read direction at the time.
# One read direction should fit in memory (<120GB)
if [[ $DOUBLEPASS == '-2' ]]; then
    wait
fi

# create reverse downsample file
log "$COMMAND1 <(zcat ${INDIR}/${REVERSE_PATTERN}) $SAMPLESIZE | $COMMAND2 > ${OUTDIR}/${REVERSE_OUTFILE}"
$COMMAND1 <(zcat ${INDIR}/${REVERSE_PATTERN}) $SAMPLESIZE | $COMMAND2 > ${OUTDIR}/${REVERSE_OUTFILE}
