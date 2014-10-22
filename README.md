# DOWNSAMPLING

Script to downsample a bunch of fastq files.
Reads will be selected randomly.

## Usage

```bash ./downsample indir outdir reads

with:
    indir: The input directory. The script will expect forward and reverse
           strand files found with a matching pattern.
           - forward match pattern: *_1.fastq.gz
           - reverse match pattern: *_2.fastq.gz
    outdir: The output directory. Will be created if it does not exist.
           One output file per strand will be created in this directory.
           The output file name will be the first file name in the input
           directory matched with above mentioned patterns.
    reads: The amount of reads to keep.
```

## Dependencies

This script uses [seqtk](https://github.com/lh3/seqtk) to quickly downsample
fastq files.
