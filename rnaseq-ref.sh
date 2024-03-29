#!/bin/bash

num_threads=4

indir=$1


# SE ${indir} NÃO EXISTE, SE NÃO FOI PASSADO ARGUMENTO 1 NA LINHA DE COMANDO
if [ ! ${indir} ]; then
	echo "Missing input directory."
	exit
fi

# SE ${indir} NÃO É DIRETÓRIO
if [ ! -d ${indir} ]; then
	echo "Wrong input directory (${indir})."
	exit
fi

outdir=$2

# SE ${outdir} NÃO EXISTE, SE NÃO FOI PASSADO ARGUMENTO 2 NA LINHA DE COMANDO
if [ ! ${outdir} ]; then
	echo "Missing output directory."
	exit
fi

# SE ${outdir} NÃO É DIRETÓRIO
if [ ! -d ${outdir} ]; then
	echo "Wrong output directory (${outdir})."
	exit
fi

refgtf=$3
# SE ${refgtf} NÃO EXISTE, SE NÃO FOI PASSADO ARGUMENTO 3 NA LINHA DE COMANDO
if [ ! ${refgtf} ]; then
	echo "Missing GTF file."
	exit
fi

if [ ! -e "${refgtf}" ]; then
	echo "Not found GTF file (${refgtf})."
	exit
fi

refseq=$4
# SE ${refseq} NÃO EXISTE, SE NÃO FOI PASSADO ARGUMENTO 4 NA LINHA DE COMANDO
if [ ! ${refseq} ]; then
	echo "Missing GENOME fasta file."
	exit
fi

if [ ! -e "${refseq}" ]; then
	echo "Not found GENOME fasta file (${refseq})."
	exit
fi

./preprocess3.sh "${indir}" "${outdir}"

mkdir -p ${outdir}/star_index
mkdir -p ${outdir}/star_out_pe
mkdir -p ${outdir}/star_out_se
mkdir -p ${outdir}/star_out_final
mkdir -p ${outdir}/cufflinks
mkdir -p ${outdir}/cuffmerge
mkdir -p ${outdir}/stringtie
mkdir -p ${outdir}/stringmerge
mkdir -p ${outdir}/cuffcompare
mkdir -p ${outdir}/cuffquant


for r1 in `ls ${outdir}/processed/prinseq/*.atropos_final.prinseq_1.fastq`; do
	r1_singletons=`echo ${r1} | sed 's/prinseq_1.fastq/prinseq_1_singletons.fastq/'`
	if [ ! -e "${r1_singletons}" ]; then
		touch ${r1_singletons}
	fi
	
	r2=`echo ${r1} | sed 's/prinseq_1.fastq/prinseq_2.fastq/'`
	
	if [ ! -e "${r2}" ]; then
		echo "Read 2 (${r2}) paired with Read 1 ($r1) not found."
		exit
	fi
	
	r2_singletons=`echo ${r2} | sed 's/prinseq_2.fastq/prinseq_2_singletons.fastq/'`
	if [ ! -e "${r2_singletons}" ]; then
		touch ${r2_singletons}
	fi
	
	name=`basename ${r1} | sed 's/.atropos_final.prinseq_1.fastq//'`
	
	if [ ! -e "${outdir}/star_index/SAindex" ]; then
		echo "Indexing genome (${refseq}) ..."
		# --genomeSAindexNbases 12 (sugestão do alinhador)
		# --sjdbOverhang 149 (sugestão do manual)	
		STAR 	--runThreadN        ${num_threads} \
			--runMode           genomeGenerate \
			--genomeFastaFiles  ${refseq} \
			--genomeDir         ${outdir}/star_index \
			--sjdbGTFfile       ${refgtf} \
			--genomeSAindexNbases 12 \
			--sjdbOverhang      149 \
		 > ${outdir}/star_index/STAR.index.log.out.txt \
		2> ${outdir}/star_index/STAR.index.log.err.txt
	
	fi
	
	echo "STAR alignment PE with sample ${name}: ${r1} & ${r2} ..."
	
	# --outSAMstrandField intronMotif 
	# --outFilterIntronMotifs RemoveNoncanonical 
	# (parâmetros recomendados pelo Manual para manter a compatibilidade com Cufflinks)
	mkdir -p ${outdir}/star_out_pe/${name}
	
	STAR	--runThreadN        ${num_threads} \
		--genomeDir         ${outdir}/star_index \
		--readFilesIn       ${r1} ${r2} \
		--outSAMstrandField intronMotif \
		--outFilterIntronMotifs RemoveNoncanonical \
		--sjdbGTFfile       ${refgtf} \
		--outFilterMultimapNmax 20 \
		--outFileNamePrefix ${outdir}/star_out_pe/${name}/ \
		--outSAMtype        BAM Unsorted \
		 > ${outdir}/star_out_pe/${name}/STAR.alignment_pe.log.out.txt \
		2> ${outdir}/star_out_pe/${name}/STAR.alignment_pe.log.err.txt
	
	echo "STAR alignment SE with sample ${name}: ${r1_singletons} & ${r2_singletons} ..."
	
	mkdir -p ${outdir}/star_out_se/${name}
	
	STAR	--runThreadN        ${num_threads} \
		--genomeDir         ${outdir}/star_index \
		--readFilesIn       ${r1_singletons},${r2_singletons} \
		--sjdbGTFfile       ${refgtf} \
		--outSAMtype        BAM Unsorted \
		--outFilterMultimapNmax 20 \
		--outSAMstrandField intronMotif \
		--outFileNamePrefix ./$outdir/star_out_se/${name}/ \
		 > ./${outdir}/star_out_se/${name}/STAR.alignment_se.log.out.txt \
		2> ./${outdir}/star_out_se/${name}/STAR.alignment_se.log.err.txt
	
	echo "Merging STAR alignment PE & SE (${name}) ..."
	
	mkdir -p ${outdir}/star_out_final/${name}

        # Combinar resultados do alinhamento com reads paired-end e alinhamento com reads single-end (singletons)       
	 samtools merge -@ ${num_threads} -f -n  ${outdir}/star_out_final/${name}/Aligned.out.bam \
                                                ${outdir}/star_out_pe/${name}/Aligned.out.bam \
                                                ${outdir}/star_out_se/${name}/Aligned.out.bam \
	 > ${outdir}/star_out_final/${name}/samtools.merge.log.out.txt \
	2> ${outdir}/star_out_final/${name}/samtools.merge.log.err.txt

	echo "Sorting STAR alignment final (${name}) ..."
        # Ordenando o resultado do alinhamento por coordenadas genômicas
        # - exigência para executar o cufflinks
	 samtools sort -@ ${num_threads} -o      ${outdir}/star_out_final/${name}/Aligned.out.sorted.bam \
                                                ${outdir}/star_out_final/${name}/Aligned.out.bam \
	 > ${outdir}/star_out_final/${name}/samtools.sort.log.out.txt \
	2> ${outdir}/star_out_final/${name}/samtools.sort.log.err.txt

	echo "Collecting alignment statistics (${name}) ..."
	
	SAM_nameSorted_to_uniq_count_stats.pl ${outdir}/star_out_final/${name}/Aligned.out.bam > ${outdir}/star_out_final/${name}/Aligned.stats.txt
	
	echo "Running Cufflinks (${name}) ..."
	
	mkdir -p ${outdir}/cufflinks/${name}
	
	cufflinks --output-dir ${outdir}/cufflinks/${name} \
		  --num-threads ${num_threads} \
		  --GTF-guide ${refgtf} \
		  --frag-bias-correct ${refseq} \
		  --multi-read-correct \
		  --library-type fr-unstranded \
		  --frag-len-mean 300 \
		  --frag-len-std-dev 50 \
		  --total-hits-norm \
		  --max-frag-multihits 20 \
		  --min-isoform-fraction 0.20 \
		  --max-intron-length 10000 \
		  --min-intron-length 100 \
		  --overhang-tolerance 4 \
		  --max-bundle-frags 999999 \
		  --max-multiread-fraction 0.45 \
		  --overlap-radius 10 \
		  --3-overhang-tolerance 300 \
		  ${outdir}/star_out_final/${name}/Aligned.out.sorted.bam \
		 > ${outdir}/star_out_final/${name}/cufflinks.log.out.txt \
		2> ${outdir}/star_out_final/${name}/cufflinks.log.err.txt


	echo "Running StringTie (${name}) ..."
	
	mkdir -p ${outdir}/stringtie/${name}
	
	stringtie ${outdir}/star_out_final/${name}/Aligned.out.sorted.bam \
		-G ${refgtf} \
		-o ${outdir}/stringtie/${name}/transcripts.gtf \
		-p ${num_threads} \
		-f 0.20 \
		-a 10 \
		-j 3 \
		-c 2 \
		-g 10 \
		-M 0.45 \
		-A ${outdir}/stringtie/${name}/gene_abundance.txt


done


echo "Running cuffmerge ..."

find ${outdir}/cufflinks/ -name 'transcripts.gtf' > ${outdir}/cuffmerge/assembly_GTF_list.txt

cuffmerge -o ${outdir}/cuffmerge/ \
	--ref-gtf ${refgtf} \
	--ref-sequence ${refseq} \
	--min-isoform-fraction 0.20 \
	--num-threads ${num_threads} \
	   ${outdir}/cuffmerge/assembly_GTF_list.txt \
	 > ${outdir}/cuffmerge/cuffmerge.log.out.txt \
	2> ${outdir}/cuffmerge/cuffmerge.log.err.txt

echo "Running stringtie merge ..."

find ${outdir}/stringtie/ -name 'transcripts.gtf' > ${outdir}/stringmerge/assembly_GTF_list.txt

stringtie --merge \
	-G ${refgtf} \
	-o ${outdir}/stringmerge/merged.gtf \
	-c 1 \
	-T 1 \
	-f 0.20 \
	-g 10 \
	-i \
	${outdir}/stringmerge/assembly_GTF_list.txt

cuffcompare	-r ${refgtf} \
		-s ${refseq} \
		-o ${outdir}/cuffcompare/stringmerge \
		${outdir}/stringmerge/merged.gtf \
		 > ${outdir}/stringmerge/cuffcompare.log.out.txt \
		2> ${outdir}/stringmerge/cuffcompare.log.err.txt


biogroup_label=()
for bamfile in `ls ${outdir}/star_out_final/*/Aligned.out.sorted.bam`; do
	name=`basename $(dirname ${bamfile})`
	echo "Running cuffquant using sample ${name} with ${outdir}/stringmerge/merged.gtf as reference ..."
	mkdir -p ${outdir}/cuffquant/${name}

	cuffquant 	--output-dir ${outdir}/cuffquant/${name} \
			--frag-bias-correct ${refseq} \
			--multi-read-correct \
			--num-threads ${num_threads} \
			--library-type fr-unstranded \
			--frag-len-mean 300 \
			--frag-len-std-dev 50 \
			--max-bundle-frags 9999999 \
			--max-frag-multihits 20 \
			${outdir}/stringmerge/merged.gtf \
			${bamfile} \
		 > ${outdir}/cuffquant/${name}/cuffquant.log.out.txt \
		2> ${outdir}/cuffquant/${name}/cuffquant.log.err.txt

	groupname=`echo ${name} | sed 's/[0-9]\+$//'`
	biogroup_label=($(printf "%s\n" ${biogroup_label[@]} ${groupname} | sort -u ))

done
biogroup_files=()

echo "Running Differential Expression Analysis ..."
for label in ${biogroup_label[@]}; do
	echo -e "\tCollecting .cxb files for ${label} ..."
	group=()
	for cxbfile in `ls ${outdir}/cuffquant/${label}*/abundances.cxb`; do
		echo -e "\t\tFound ${cxbfile}"
		group=(${group[@]} "${cxbfile}")
	done
	biogroup_files=(${biogroup_files[@]} $(IFS=, ; echo "${group[*]}") )
done

echo -e "\tRunning cuffnorm & cuffdiff ..."
echo -e "\t\tLabels.: " $(IFS=, ; echo "${biogroup_label[*]}")
echo -e "\t\tFiles..: " ${biogroup_files[*]}

echo -e "\t\t\tGenerating abundance matrices (cuffnorm) ..."

mkdir -p ${outdir}/cuffnorm/

cuffnorm 	--output-dir ${outdir}/cuffnorm \
 		--labels $(IFS=, ; echo "${biogroup_label[*]}") \
 		--num-threads ${num_threads} \
		--library-type fr-unstranded \
 		--library-norm-method geometric \
		--output-format simple-table \
 		${outdir}/stringmerge/merged.gtf \
 		${biogroup_files[*]} \
 	 	> ${outdir}/cuffnorm/cuffdiff.log.out.txt \
 		2> ${outdir}/cuffnorm/cuffdiff.log.err.txt


echo -e "\t\t\tAnalysing differential expression (cuffdiff) ..."

mkdir -p ${outdir}/cuffdiff/

cuffdiff 	--output-dir ${outdir}/cuffdiff \
 		--labels $(IFS=, ; echo "${biogroup_label[*]}") \
 		--frag-bias-correct ${refseq} \
 		--multi-read-correct \
 		--num-threads ${num_threads} \
 		--library-type fr-unstranded \
 		--frag-len-mean 300 \
 		--frag-len-std-dev 50 \
 		--max-bundle-frags 9999999 \
 		--max-frag-multihits 20 \
 		--total-hits-norm \
 		--min-reps-for-js-test 2 \
 		--library-norm-method geometric \
 		--dispersion-method per-condition \
 		--min-alignment-count 10 \
 		${outdir}/stringmerge/merged.gtf \
 		${biogroup_files[*]} \
 	 	> ${outdir}/cuffdiff/cuffdiff.log.out.txt \
 		2> ${outdir}/cuffdiff/cuffdiff.log.err.txt
