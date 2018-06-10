# This script tests the regionCounts function.
# library(csaw); library(testthat); source("test-region.R")

source("simsam.R")

library(Rsamtools)
CHECKFUN <- function(bam.files, regions, param, fraglen=200, final.len=NA) {
	y <- regionCounts(bam.files, regions=regions, ext=fraglen, param=param)
    all.chrs <- scanBamHeader(bam.files[1])[[1]]$targets
    genome <- GRanges(names(all.chrs), IRanges(1, all.chrs))

    total.reads <- integer(length(bam.files))
    for (f in seq_along(bam.files)) {
        for (r in seq_along(genome)) { 
            chosen <- as.logical(seqnames(genome[r])==seqnames(regions)) 

            if (length(param$restrict) && as.logical(!seqnames(genome)[r] %in% param$restrict)) {
                expect_identical(assay(y)[chosen,f], integer(sum(chosen)))
            } else {
                collected <- extractReads(bam.files[f], genome[r], param=param, ext=fraglen)
                expect_identical(assay(y)[chosen,f], countOverlaps(regions[chosen], collected))
                total.reads[f] <- total.reads[f] + length(collected)
            }
		}
	}

    expect_identical(total.reads, y$totals)
    return(y)
}

tempdir <- tempfile()
dir.create(tempdir)
chromos<-c(chrA=1000, chrB=5000)

set.seed(40001)
test_that("regionCounts works with SE data", {
    for (rparam in list(readParam(), 
                        readParam(minq=10),
                        readParam(dedup=TRUE),
                        readParam(forward=FALSE),
                        readParam(forward=TRUE),
                        readParam(discard=makeDiscard(10, 100, chromos)),
                        readParam(restrict="chrB")
                        )) {
    	bam.files <-c(regenSE(1000, chromos, file.path(tempdir, "A")), 
                      regenSE(2000, chromos, file.path(tempdir, "B")))
        extractor <- generateWindows(chromos, 5, 500)
        CHECKFUN(bam.files, extractor, param=rparam)
    }

    # Checking extension strategies.
    for (ext.param in list(NA, 10, 100, 100)) {
    	bam.files <-c(regenSE(1000, chromos, file.path(tempdir, "A")), 
                      regenSE(1500, chromos, file.path(tempdir, "B")))
        extractor <- generateWindows(chromos, 5, 500)
        CHECKFUN(bam.files, extractor, param=rparam, fraglen=ext.param)
   }

    # Checking restriction strategies.
    bam.files <-c(regenSE(600, chromos, file.path(tempdir, "A")), 
                  regenSE(500, chromos, file.path(tempdir, "B")))
    extractor <- generateWindows(chromos, 5, 500)
    y1 <- CHECKFUN(bam.files, extractor, param=readParam())
    y2 <- CHECKFUN(bam.files, extractor, param=readParam(restrict=names(chromos)))
    expect_identical(assay(y1), assay(y2))
    expect_identical(y1$totals, y2$totals)
})

set.seed(40002)
test_that("regionCounts works with PE data", {
    for (rparam in list(readParam(pe="both"), 
                        readParam(pe="both", max.frag=1e8),
                        readParam(pe="both", max.frag=200))) {
    	bam.files <-c(regenPE(10000, chromos, file.path(tempdir, "A")), 
                      regenPE(11000, chromos, file.path(tempdir, "B")))
        extractor <- generateWindows(chromos, 5, 500)
        CHECKFUN(bam.files, extractor, param=rparam)
    }

    # Checking alternative counting from PE data.
    for (rparam in list(readParam(pe="first"), 
                        readParam(pe="second"))) {
    	bam.files <-c(regenPE(20000, chromos, file.path(tempdir, "A")), 
                      regenPE(10000, chromos, file.path(tempdir, "B")))
        extractor <- generateWindows(chromos, 5, 500)
        CHECKFUN(bam.files, extractor, param=rparam, fraglen=100)
        CHECKFUN(bam.files, extractor, param=rparam, fraglen=NA)
   }
})

set.seed(40002)
test_that("regionCounts works with silly inputs", {
    # Doesn't fail with no counts.
    obam <- regenSE(0L, chromos, outfname=tempfile())
    extractor <- generateWindows(chromos, 5, 500)
    out <- regionCounts(obam, extractor)
    expect_true(all(assay(out)==0))
    expect_identical(out$totals, 0L)

    # Throws a warning when input is stranded.
    strand(extractor) <- sample(c("+", "*"), length(extractor), replace=TRUE)
    expect_warning(out <- regionCounts(obam, extractor), "ignoring strandedness")
})