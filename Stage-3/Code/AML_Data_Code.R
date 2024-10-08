# START OF CODE

# Required packages

library(gplots)
library(TCGAbiolinks)
library(tidyverse)
library(SummarizedExperiment)
library(edgeR)
library(org.Hs.eg.db)
library(ggplot2)

# Metadata

Metadata_AML <- read.csv("https://raw.githubusercontent.com/Naren037/hackbio-cancer-internship/refs/heads/main/TASK%203/Datasets/AML%20Metadata.csv", row.names=1)

# Data Mining using TCGABiolinks

query_primary <-GDCquery(project = 'TARGET-AML',
                      data.category  = "Transcriptome Profiling", 
                      data.type = "Gene Expression Quantification",
                      experimental.strategy = "RNA-Seq",
                      workflow.type = "STAR - Counts",
                      sample.type = "Primary Blood Derived Cancer - Bone Marrow")

query_recurrent <-GDCquery(project = 'TARGET-AML',
                         data.category  = "Transcriptome Profiling", 
                         data.type = "Gene Expression Quantification",
                         experimental.strategy = "RNA-Seq",
                         workflow.type = "STAR - Counts",
                         sample.type = "Recurrent Blood Derived Cancer - Bone Marrow")

Output_query_primary <- getResults(query_primary)
Output_query_recurrent <- getResults(query_recurrent)

# Filtering for 20 cases in each criteria

AML_Recurrent <- as.data.frame(Output_query_recurrent[1:20, ])
AML_Primary <- as.data.frame(Output_query_primary[1:20, ])

AML_Primary_20cases <- AML_Primary$cases
query_primary_20cases <-GDCquery(project = 'TARGET-AML',
                         data.category  = "Transcriptome Profiling", 
                         data.type = "Gene Expression Quantification",
                         experimental.strategy = "RNA-Seq",
                         workflow.type = "STAR - Counts",
                         sample.type = "Primary Blood Derived Cancer - Bone Marrow",
                         barcode = AML_Primary_20cases)
GDCdownload(query_primary_20cases)
GDCprepare(query_primary_20cases, summarizedExperiment = T)
AML_Primary_prep <- GDCprepare(query_primary_20cases, summarizedExperiment = T)
AML_Primary_Dataset <- assay(AML_Primary_prep, 'unstranded')
AML_Primary_Dataset <- as.data.frame(AML_Primary_Dataset)

AML_Recurrent_20cases <- AML_Recurrent$cases
query_recurrent_20cases <-GDCquery(project = 'TARGET-AML',
                                 data.category  = "Transcriptome Profiling", 
                                 data.type = "Gene Expression Quantification",
                                 experimental.strategy = "RNA-Seq",
                                 workflow.type = "STAR - Counts",
                                 sample.type = "Recurrent Blood Derived Cancer - Bone Marrow",
                                 barcode = AML_Recurrent_20cases)
GDCdownload(query_recurrent_20cases)
GDCprepare(query_recurrent_20cases, summarizedExperiment = T)
AML_Recurrent_prep <- GDCprepare(query_recurrent_20cases, summarizedExperiment = T)
AML_Recurrent_Dataset <- assay(AML_Recurrent_prep, 'unstranded')
AML_Recurrent_Dataset <- as.data.frame(AML_Recurrent_Dataset)

# Pre-processing 1 - Adjusting NA values 

AML_Primary_Dataset[is.na(AML_Primary_Dataset)] <- rowMeans(AML_Primary_Dataset, na.rm = TRUE)
AML_Recurrent_Dataset[is.na(AML_Recurrent_Dataset)] <- rowMeans(AML_Recurrent_Dataset, na.rm = TRUE)

# Pre-processing 2 - Normalization using Trimmed mean of M values -> Adjusts differences in sample variation and sequencing depths

combined_counts <- data.frame(AML_Primary_Dataset, AML_Recurrent_Dataset)
dge_combined <- DGEList(counts = combined_counts, group = NULL)
dge_combined <- calcNormFactors(dge_combined)
dge_combined_TMM <- cpm(dge_combined, log = F)


# Pre-processing 3 - Upper Quantile filter of genes -> Removes lowly expressed genes

dataFilt <- TCGAanalyze_Filtering(
  tabDF = dge_combined_TMM,
  method = "quantile",
  qnt.cut =  0.75)
   
# Splitting the pre-processed data into primary and recurrent groups for DGE Analysis

dge_Primary_TMM <- dataFilt[,1:20]  #dge_combined_TMM[,1:20]
dge_Recurrent_TMM <- dataFilt[,21:40] #dge_combined_TMM[,21:40]

# Differential Gene Expression Analysis using TCGAnalyze with extremely stringent cut-offs for Biomarker discovery

dataDEGs <- TCGAanalyze_DEA(
             mat1 = dge_Primary_TMM,
             mat2 = dge_Recurrent_TMM,
             Cond1type = "Primary",
             Cond2type = "Recurrent",
             fdr.cut = 0.0005,
             logFC.cut = 4,
             method = "glmLRT")

plotdata <- dataDEGs # for further plots

# Retrieving gene names

ensembl_ids <- rownames(dataDEGs)
ensembl_ids_clean <- gsub("\\..*", "", ensembl_ids)
gene_symbols <- mapIds(
       x = org.Hs.eg.db,           
       keys = ensembl_ids_clean,        
       column = "SYMBOL",          
       keytype = "ENSEMBL",       
       multiVals = "first")
dataDEGs <- data.frame(gene_symbols, dataDEGs)
dataDEGs$gene_name = NULL
dataDEGs$gene_type = NULL
print(gene_symbols)

# Heatmap of DEGs

heat.data <- dataFilt[rownames(plotdata),]
plotcolnames <- t(AML.Metadata$Subtype)
colnames(heat.data) <- plotcolnames
rownames(heat.data) <- dataDEGs$gene_symbols

heatmap.2(as.matrix(heat.data),
          Rowv = F,
          Colv = F,
          dendrogram = "none",
          scale = "row",
          trace = "none",
          col = bluered(300),
          cexRow = 0.6,
          cexCol = 0.7,
          keysize = 1,
          key.title = 'Expression',
          margins = c(7,7),
          main = 'Differentially Expressed Genes',
          xlab = 'Sample Type',
          ylab = 'Genes')

# Bubble plot - DGE Analysis

ggplot(dataDEGs, aes(x = logFC, y = gene_symbols, size = -log10(PValue))) +
  geom_point(alpha=0.5)

# Exporting DGE analysis findings

write.csv(dataDEGs, "AML_DEGs.csv")

# Functional Enrichment 
# Gene Ontology (GO) and Pathway enrichment by DEGs list

  Genelist <- dataDEGs$gene_symbols
  ansEA <- TCGAanalyze_EAcomplete(
      TFname = "DEA genes Primary Vs Recurrent",
      RegulonList = Genelist)

  
# Enrichment Analysis EA (TCGAVisualize)
# Gene Ontology (GO) and Pathway enrichment barPlot
  
TCGAvisualize_EAbarplot(
      tf = rownames(ansEA$ResBP),
      GOBPTab = head(ansEA$ResBP),
      GOCCTab = ansEA$ResCC,
      GOMFTab = ansEA$ResMF,
      PathTab = ansEA$ResPat,
      nRGTab = Genelist,
      nBar = 10
  )

# Print top 5 GO Biological processes

for (i in 1:5) { print(ansEA[["ResBP"]][[i]])}

# END OF CODE 




