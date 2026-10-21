# Biostar Handbook - Human immunodeficiency virus 1 

Detailing steps below to import genomic data of HIV 1 strain and visualise using IGV

### Setting variable names
Assign variable with values. 
* Name - improve readability 
* ACC - accession number from NCBI
* EFETCH - function that downloads records from ICBI database

```sh
NAME := HIV_virus1
ACC  := NC_001802.1
EFETCH := https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=$(ACC)
```

### Create directories for FASTA and GFF files
FASTA file contains the sequencing data while GFF file contains information on where genes are located on genome, information of codons? — *need to confirm* \
Fai and tbi files are used for indexing the FASTA and GFF files — *need to confirm*

```sh
FASTA_DIR := fasta
FASTA     := $(FASTA_DIR)/$(NAME).fna
FASTA_IDX := $(FASTA).fai

GFF_DIR := gff
GFF_RAW := $(GFF_DIR)/$(NAME).original.gff
GFF_GZ  := $(GFF_DIR)/$(NAME).gff.gz
GFF_IDX := $(GFF_GZ).tbi

IGV  ?= /Applications/IGV_2.16.0.app/Contents/MacOS/IGV
PORT := 60151
```

### Housekeeping 
Names with a leading dot tell `make` how to behave, rather than files to build \
`.PHONY`: all igv clean — tells the system that all, igv and clean are **actions, not files**. \
`.DELETE_ON_ERROR` — deletes a target file if its recipe falls — *how does it know when the recipe falls though?*

```sh
.PHONY: all igv clean
.DELETE_ON_ERROR:
```

### Visualising in IGV
Before `igv` can run, FASTA_IDX and GFF_IDX are pre requisites. \
`printf 'new\ngenome "%s"\nload "%s"\n' "$(CURDIR)/$(FASTA)" "$(CURDIR)/$(GFF_GZ)" | nc` sends information to IGV on which files to load 

```sh
all: $(FASTA_IDX) $(GFF_IDX)

# Build and index everything, start IGV if its batch port is closed, then
# send commands to load the genome and annotation.
igv: all
	@if ! nc -z localhost $(PORT) 2>/dev/null; then \
	  echo "Starting IGV..."; \
	  $(IGV) > /dev/null 2>&1 & \
	  until nc -z localhost $(PORT) 2>/dev/null; do sleep 1; done; \
	fi
	printf 'new\ngenome "%s"\nload "%s"\n' "$(CURDIR)/$(FASTA)" "$(CURDIR)/$(GFF_GZ)" | nc -w 5 localhost $(PORT)
```

### Create new folders for FASTA and GFF files 
```sh
$(FASTA_DIR) $(GFF_DIR):
	mkdir -p $@
```

### Import FASTA files 
Necessary pre-requisites: FASTA folder created \
FASTA_IDX is the indexed version of the FASTA file. Records each sequence's name, length and line width. the `.fai` file needs to be in the same folder as the `.fna` file. The `.fna` file will have the actual sequences and IGV can use the `.fai` file for the table of names and lengths.
```sh
# --- FASTA ---
$(FASTA): | $(FASTA_DIR)
	bio fetch $(ACC) --format fasta > $@

$(FASTA_IDX): $(FASTA)
	samtools faidx $<
```

### Import GFF files

```sh
# ---- GFF ----
# Order-only dependency on the FASTA keeps the two NCBI requests sequential.
$(GFF_RAW): | $(GFF_DIR) $(FASTA)
	bio fetch $(ACC) --format gff > $@
```




















### FULL CODE BELOW
```sh
NAME := HIV_virus1
ACC  := NC_001802.1
EFETCH := https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=$(ACC)

FASTA_DIR := fasta
FASTA     := $(FASTA_DIR)/$(NAME).fna
FASTA_IDX := $(FASTA).fai

GFF_DIR := gff
GFF_RAW := $(GFF_DIR)/$(NAME).original.gff
GFF_GZ  := $(GFF_DIR)/$(NAME).gff.gz
GFF_IDX := $(GFF_GZ).tbi

IGV  ?= /Applications/IGV_2.16.0.app/Contents/MacOS/IGV
PORT := 60151

.PHONY: all igv clean
.DELETE_ON_ERROR:

all: $(FASTA_IDX) $(GFF_IDX)

# Build and index everything, start IGV if its batch port is closed, then
# send commands to load the genome and annotation.
igv: all
	@if ! nc -z localhost $(PORT) 2>/dev/null; then \
	  echo "Starting IGV..."; \
	  $(IGV) > /dev/null 2>&1 & \
	  until nc -z localhost $(PORT) 2>/dev/null; do sleep 1; done; \
	fi
	printf 'new\ngenome "%s"\nload "%s"\n' "$(CURDIR)/$(FASTA)" "$(CURDIR)/$(GFF_GZ)" | nc -w 5 localhost $(PORT)

$(FASTA_DIR) $(GFF_DIR):
	mkdir -p $@

# --- FASTA ---
$(FASTA): | $(FASTA_DIR)
	curl -fL --retry 3 -o $@.tmp "$(EFETCH)&rettype=fasta&retmode=text"
	mv $@.tmp $@

$(FASTA_IDX): $(FASTA)
	samtools faidx $<

# --- GFF ---
# Order-only dependency on the FASTA keeps the two NCBI requests sequential.
$(GFF_RAW): | $(GFF_DIR) $(FASTA)
	curl -fL --retry 3 -o $@.tmp "$(EFETCH)&rettype=gff3&retmode=text"
	mv $@.tmp $@

# Tabix needs a coordinate-sorted, BGZF-compressed file: headers first,
# then features sorted by sequence name and start position.
$(GFF_GZ): $(GFF_RAW)
	( grep '^#' $< ; \
	  grep -v '^#' $< | grep -v '^[[:space:]]*$$' | sort -t "$$(printf '\t')" -k1,1 -k4,4n ) \
	  | bgzip > $@.tmp
	mv $@.tmp $@

$(GFF_IDX): $(GFF_GZ)
	tabix -f -p gff $<

clean:
	rm -f $(FASTA) $(FASTA).tmp $(FASTA_IDX)
	rm -f $(GFF_RAW) $(GFF_RAW).tmp $(GFF_GZ) $(GFF_GZ).tmp $(GFF_IDX)
	rmdir $(FASTA_DIR) $(GFF_DIR) 2>/dev/null || true
```