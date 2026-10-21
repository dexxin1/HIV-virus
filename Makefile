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
	bio fetch $(ACC) --format fasta > $@

$(FASTA_IDX): $(FASTA)
	samtools faidx $<

# --- GFF ---
# Order-only dependency on the FASTA keeps the two NCBI requests sequential.
$(GFF_RAW): | $(GFF_DIR) $(FASTA)
	bio fetch $(ACC) --format gff > $@.tmp
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