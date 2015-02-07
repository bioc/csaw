getPESizes <- function(bam.file, param=readParam(pe="both")) 
# This function takes a BAM file and reads it to parse the size of the PE fragments. It then
# returns a vector of sizes which can be plotted for diagnostics. The length of the vector
# will also tell you how many read pairs were considered valid. The total number of reads, the
# number of singletons and the number of interchromosomal pairs is also reported.
# 
# written by Aaron Lun
# a long long time ago
# last modified 12 December 2014
{
	if (param$pe!="both") { stop("paired-end inputs required") }
    extracted.chrs <- .activeChrs(bam.file, param$restrict)

	singles <- totals <- others <- one.unmapped <- 0L
	stopifnot(length(bam.file)==1L)
	norm.list <- loose.names.1 <- loose.names.2 <- list()

	for (i in 1:length(extracted.chrs)) {
		chr <- names(extracted.chrs)[i]
		where <- GRanges(chr, IRanges(1L, extracted.chrs[i]))
		reads <- .extractSE(bam.file, extras=c("qname", "flag", "isize"), where=where, param=param) 

		# Getting rid of unpaired reads.
		totals <- totals + length(reads$flag)
		is.single <- bitwAnd(reads$flag, 0x1)==0L
		singles <- singles + sum(is.single)
 		only.one <- bitwAnd(reads$flag, 0x8)!=0L
		one.unmapped <- one.unmapped + sum(!is.single & only.one)
	    for (x in names(reads)) { reads[[x]] <- reads[[x]][!is.single & !only.one] }	
		
		# Identifying valid reads.
		okay <- .yieldInterestingBits(reads, extracted.chrs[i], diag=TRUE)
		norm.list[[i]] <- okay$size
		left.names <- reads$qname[!okay$is.ok]
		left.flags <- reads$flag[!okay$is.ok]
		
		# Setting up some more filters.
		on.same.chr <- reads$isize[!okay$is.ok]!=0L
		is.first <- bitwAnd(left.flags, 0x40)!=0L
		is.second <- bitwAnd(left.flags, 0x80)!=0L
		
		# Identifying improperly orientated pairs and reads with unmapped counterparts.
		leftovers.first <- left.names[on.same.chr & is.first]
		leftovers.second <- left.names[on.same.chr & is.second]
		has.pair <- sum(leftovers.first %in% leftovers.second)
		others <- others + has.pair
		one.unmapped <- one.unmapped + length(leftovers.first) + length(leftovers.second) - 2L*has.pair 

		# Collecting the rest to match inter-chromosomals.
		loose.names.1[[i]] <- left.names[!on.same.chr & is.first]
		loose.names.2[[i]] <- left.names[!on.same.chr & is.second]
	}

	# Checking whether a read is positively matched to a mapped counterpart on another chromosome.
	# If not, then it's just an read in an unmapped pair.
	loose.names.1 <- unlist(loose.names.1)
	loose.names.2 <- unlist(loose.names.2)
	inter.chr <- sum(loose.names.1 %in% loose.names.2)
	one.unmapped <- one.unmapped + length(loose.names.2) + length(loose.names.1) - inter.chr*2L

	# Returning sizes and some diagnostic data.
    return(list(sizes=unlist(norm.list), diagnostics=c(total=totals, single=singles, 
		mate.unmapped=one.unmapped, unoriented=others, inter.chr=inter.chr)))
}

##################################

.yieldInterestingBits <- function(reads, clen, max.frag=Inf, diag=FALSE)
# This figures out what the interesting reads are, given a list of 
# read names, flags, positions and qwidths. In particular, reads have
# to be properly paired in an inward conformation, without one read
# overrunning the other (if the read lengths are variable).
#
# written by Aaron Lun
# 15 April 2014
{ 
	if (max.frag <= 0L) {
		return(list(pos=integer(0), size=integer(0), is.ok=logical(length(reads$flag))))
	}

	# Figuring out the strandedness and the read number.
 	is.forward <- bitwAnd(reads$flag, 0x10) == 0L 
 	is.mate.reverse <- bitwAnd(reads$flag, 0x20) != 0L
	should.be.left <- is.forward & is.mate.reverse
	should.be.right <- !is.forward & !is.mate.reverse
    is.first <- bitwAnd(reads$flag, 0x40) != 0L
	is.second <- bitwAnd(reads$flag, 0x80) != 0L	
	stopifnot(all(is.first!=is.second))

	# Matching the reads in each pair so only valid PEs are formed.
	set.first.A <- should.be.left & is.first
	set.second.A <- should.be.right & is.second
	set.first.B <- should.be.left & is.second
	set.second.B <- should.be.right & is.first
	corresponding.1 <- match(reads$qname[set.first.A], reads$qname[set.second.A])
	corresponding.2 <- match(reads$qname[set.first.B], reads$qname[set.second.B])

	hasmatch <- logical(length(reads$flag))
	hasmatch[set.first.A] <- !is.na(corresponding.1)
	hasmatch[set.first.B] <- !is.na(corresponding.2)
	corresponding <- integer(length(reads$flag))
	corresponding[set.first.A] <- which(set.second.A)[corresponding.1]
	corresponding[set.first.B] <- which(set.second.B)[corresponding.2]

	# Selecting the read pairs.
	fpos <- reads$pos[hasmatch]
	fwidth <- reads$qwidth[hasmatch]
	rpos <- reads$pos[corresponding[hasmatch]]
	rwidth <- reads$qwidth[corresponding[hasmatch]]

	# Allowing only valid PEs.
	fend <- pmin(fpos+fwidth, clen+1L)
	rend <- pmin(rpos+rwidth, clen+1L)
	total.size <- rend - fpos
    valid <- fpos <= rpos & fend <= rend & total.size <= max.frag
	fpos <- fpos[valid]
	total.size <- total.size[valid]

	if (diag) { 
		is.ok <- logical(length(reads$flag))
		is.ok[hasmatch][valid] <- TRUE
		is.ok[corresponding[hasmatch]][valid] <- TRUE
		return(list(pos=fpos, size=total.size, is.ok=is.ok))
	}
	return(list(pos=fpos, size=total.size))
}

##################################