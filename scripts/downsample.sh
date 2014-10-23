#!/bin/bash

# exit on errr
set -e

##################
# MATCH PATTERNS #
##################

# Change the file matching pattern here if needed

FORWARD_PATTERN='*_1.fastq.gz'
REVERSE_PATTERN='*_2.fastq.gz'

#########
# USAGE #
#########

if [[ $# < 3 ]]; then
    echo "Usage:"
    echo "	$0 indir outdir reads"
    echo ""
    echo "	with:"
    echo "		indir: The input directory. The script will expect forward and reverse"
    echo "		       strand files found with a matching pattern."
    echo "		       - forward match pattern: $FORWARD_PATTERN"
    echo "		       - reverse match pattern: $REVERSE_PATTERN"
    echo "		outdir: The output directory. Will be created if it does not exist."
    echo "		       One output file per strand will be created in this directory."
    echo "		       The output file name will be the first file name in the input"
    echo "		       directory matched with above mentioned patterns."
    echo "		reads: The amount of reads to keep."

    exit 1
fi

##########
# params #
##########

INDIR=$1
OUTDIR=$2
READS=$3

[[ ! -e $OUTDIR ]] && mkdir $OUTDIR

SEQTK_DIR=`readlink -f $0`
SEQTK_DIR=`dirname $SEQTK_DIR`/../bin/

########
# RUN! #
########

# get first file name - forward
FORWARD_OUTFILE=`ls -1 ${INDIR}/${FORWARD_PATTERN} | head -1`
if [[ ! -e $FORWARD_OUTFILE ]]; then
    >&2 echo 'No forward strands found!'
    exit 1
fi
FORWARD_OUTFILE=`basename $FORWARD_OUTFILE`

# get first file name - reverse
REVERSE_OUTFILE=`ls -1 ${INDIR}/${REVERSE_PATTERN} | head -1`
if [[ ! -e $REVERSE_OUTFILE ]]; then
    >&2 echo 'No reverse strands found!'
    exit 1
fi
REVERSE_OUTFILE=`basename $REVERSE_OUTFILE`

# get a random number (range 0-32k)
SEED=$RANDOM

echo 'Input files FORWARD:'
ls ${INDIR}/${FORWARD_PATTERN}

echo 'Input files REVERSE:'
ls ${INDIR}/${REVERSE_PATTERN}

echo 'Running:'
# create a temp file to store the PID of seqtk
PIDFILE=`mktemp`
# create forward downsample file -- and put it in the background
COMMAND1="${SEQTK_DIR}/seqtk sample -s $SEED"
COMMAND2="gzip --to-stdout"
echo "$COMMAND1 <(zcat ${INDIR}/${FORWARD_PATTERN}) $READS | $COMMAND2 > ${OUTDIR}/${FORWARD_OUTFILE} &"
( echo $BASHPID > $PIDFILE; exec $COMMAND1 <(zcat ${INDIR}/${FORWARD_PATTERN}) $READS ) | $COMMAND2 > ${OUTDIR}/${FORWARD_OUTFILE} &

# remove the background seqtk on ctrl+c
trap "kill `cat $PIDFILE`; rm $PIDFILE" INT KILL

# create reverse downsample file
echo "$COMMAND1 <(zcat ${INDIR}/${REVERSE_PATTERN}) $READS | $COMMAND2 > ${OUTDIR}/${REVERSE_OUTFILE}"
$COMMAND1 <(zcat ${INDIR}/${REVERSE_PATTERN}) $READS | $COMMAND2 > ${OUTDIR}/${REVERSE_OUTFILE}
