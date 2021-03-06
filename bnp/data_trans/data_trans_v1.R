library(readr)
library(data.table)
library(zoo)
library(caret)
library(e1071)
library(Matrix)
library(proxy)
library(qlcMatrix)
library(cccd)
library(igraph)
library(gtools)
library(plyr)
library(dplyr)
library(sqldf)
setwd("/media/branden/SSHD1/kaggle/bnp")
# Load data
t1 <- data.table(read_csv("./train.csv"))
s1 <- data.table(read_csv("./test.csv"))

t1$filter <- 0
s1$filter <- 2

s1 <- s1[,target:=-1]
# Combine into 1 data frame
l <- list(t1, s1)
ts1 <- data.table(do.call(smartbind,l))
# Give blank factor levels a name
charCols <- colnames(ts1)[sapply(ts1, is.character)]

for (i in 1:length(charCols)){
  set(ts1, i=which(is.na(ts1[[charCols[i]]])), j=charCols[i], value="NULL")
  # ts1[,charCols[i],with=FALSE]ts1[,charCols[i],with=FALSE]=="" <- "NULL"
}

#Convert character columns to factor
ts1 <- ts1[,(charCols):=lapply(.SD, as.factor),.SDcols=charCols]


pp <- preProcess(ts1[ts1$filter==0, -c("filter"), with=FALSE], method=c("zv", "medianImpute"))
ts1 <- predict(pp, ts1)

# Function from Owen's Amazon competition (https://github.com/owenzhang/Kaggle-AmazonChallenge2013/blob/master/__final_utils.R)
#2 way count
my.f2cnt<-function(th2, vn1, vn2, filter=TRUE) {
  df<-data.frame(f1=th2[,vn1,with=FALSE], f2=th2[,vn2,with=FALSE], filter=filter)
  colnames(df) <- c("f1", "f2", "filter")
  sum1<-sqldf("select f1, f2, count(*) as cnt from df where filter=1 group by 1,2")
  tmp<-sqldf("select b.cnt from df a left join sum1 b on a.f1=b.f1 and a.f2=b.f2")
  tmp$cnt[is.na(tmp$cnt)]<-0
  return(tmp$cnt)
}

my.f3cnt <- function(th2, vn1, vn2, vn3, filter=TRUE) {
  df<-data.frame(f1=th2[,vn1, with=FALSE], f2=th2[,vn2, with=FALSE], f3=th2[, vn3, with=FALSE], filter=filter)
  colnames(df) <- c("f1", "f2", "f3", "filter")
  sum1<-sqldf("select f1, f2, f3, count(*) as cnt from df where filter=1 group by 1, 2, 3")
  tmp<-sqldf("select b.cnt from df a left join sum1 b on a.f1=b.f1 and a.f2=b.f2 and a.f3=b.f3")
  tmp$cnt[is.na(tmp$cnt)]<-0
  return(tmp$cnt)
}

int3WayBool <- function(th2, vn1, vn2, vn3, filter=TRUE) {
  df<-data.frame(f1=th2[,vn1, with=FALSE], f2=th2[,vn2, with=FALSE], f3=th2[, vn3, with=FALSE], filter=filter)
  colnames(df) <- c("f1", "f2", "f3", "filter")
  tmp <- ifelse(df$f1>0 & df$f2>0 & df$f3>0, apply(df[,c("f1","f2","f3")], MARGIN = 1, sum, na.rm=TRUE), 0)
  return(tmp)
}

#####################
## Log feature ratios
#####################

pairs <- combn(charCols, 2, simplify=FALSE)
for (i in 1:length(pairs)){
  name <- paste0(pairs[[i]][1], "_", pairs[[i]][2], "_cnt2") 
  tmp <- my.f2cnt(ts1, pairs[[i]][1], pairs[[i]][2])
  if (sum(tmp[ts1$filter==0]) == 0) next else # exclude columns with no variance in the training set
    ts1[,name] <- tmp
}


# for (i in 1:length(pairs)){
#   name <- paste0(pairs[[i]][1], "_", pairs[[i]][2],"_ratio") 
#   tmp <- as.data.frame(featCast[,pairs[[i]][1], with=FALSE] / featCast[,pairs[[i]][2], with=FALSE])
#   tmp <- do.call(data.frame,lapply(tmp, function(x) replace(x, is.infinite(x), 99999)))
#   tmp <- replace(tmp, is.na(tmp), -1)
#   ts1[,name] <- tmp
# }

#####################
# 3 way interaction indicator
#####################
# triplets <- combn(charCols, 3, simplify=FALSE)
# for (i in 1:length(triplets)){
#   name <- paste0(triplets[[i]][1], "_", triplets[[i]][2], "_", triplets[[i]][3], "_int") 
#   tmp <- int3WayBool(featCast, triplets[[i]][1], triplets[[i]][2], triplets[[i]][3])
#   if (sum(tmp[ts1$filter==0]) == 0) next else # exclude columns with no variance in the training set
#     ts1[,name] <- tmp
# }

############
## PAIRWISE CORRELATIONS -- code & idea from Tian Zhou - teammate in Homesite competition
############
# Remove features with correlations equal to 1
numCols <- colnames(ts1[,!colnames(ts1) %in% c("ID","target","filter"),with=FALSE])[sapply(ts1[,!colnames(ts1) %in% c("ID","target","filter"),with=FALSE], is.numeric)]
featCor = cor(ts1[,numCols,with=FALSE])
hc = findCorrelation(featCor, cutoff=0.999999, names=TRUE)  
hc = sort(hc)
ts1 = ts1[,-hc,with=FALSE]

pairs <- combn(names(ts1[,colnames(ts1) %in% numCols,with=FALSE]), 2, simplify=FALSE)
df <- data.frame(Variable1=rep(0,length(pairs)), Variable2=rep(0,length(pairs)), 
                 AbsCor=rep(0,length(pairs)))
for(i in 1:length(pairs)){
  df[i,1] <- pairs[[i]][1]
  df[i,2] <- pairs[[i]][2]
  df[i,3] <- round(abs(cor(ts1[,pairs[[i]][1],with=FALSE], ts1[,pairs[[i]][2],with=FALSE])),4)
}
pairwiseCorDF <- df[order(df$AbsCor, decreasing=TRUE),]
row.names(pairwiseCorDF) <- 1:length(pairs)

list_out<-list()
for(i in 1:100){
  list_out[[length(list_out)+1]] <- list(pairwiseCorDF[i,1],pairwiseCorDF[i,2])
}

corFeat <- list_out
for (i in 1:length(corFeat)) {
  W=paste(corFeat[[i]][[1]],corFeat[[i]][[2]],"cor",sep="_")
  ts1[,W] <-ts1[,corFeat[[i]][[1]],with=FALSE]-ts1[,corFeat[[i]][[2]],with=FALSE]
}
######################################################

# Scale variables so a few don't overpower the helper columns
pp <- preProcess(ts1[filter==0,!colnames(ts1) %in% c("ID","target","filter"),with=FALSE], method=c("zv","center","scale","medianImpute"))
ts1_pp <- predict(pp, ts1)



############
## Helper columns
############
summ <- as.data.frame(ts1_pp[ts1_pp$filter==0, colnames(ts1_pp) %in% c("target",numCols),with=FALSE] %>% group_by(target) %>%
                        summarise_each(funs(mean)))
# Find means and sd's for columns
mn1 <- sapply(summ[,2:ncol(summ)], mean)
sd1 <- sapply(summ[,2:ncol(summ)], sd)
# Find upper and lower thresholds
hi <- mn1+2*sd1
lo <- mn1-2*sd1

helpCols <- list()
for (i in 0:1){
  tmpHi <- (summ[summ$target==i,2:ncol(summ)] - mn1)/sd1
  hiNames <- colnames(tmpHi[,order(tmpHi)][,1:30])
  loNames <- colnames(tmpHi[,order(tmpHi,decreasing = TRUE)][1:30])
  
  helpCols[[i+1]] <- c(hiNames, loNames)
  
}
names(helpCols) <- paste0("X", seq_along(helpCols)-1)

for (i in 0:1){
  ts1_pp[[ncol(ts1_pp)+1]] <- rowSums(ts1_pp[,helpCols[[i+1]], with=FALSE])
  colnames(ts1_pp)[ncol(ts1_pp)] <- paste0("X", i, "_helper")
}


write.csv(as.data.frame(helpCols), "./data_trans/helpCols_v1.csv", row.names=FALSE)
save(helpCols, file="./data_trans/helpCols_v1.rda")

##################
## Create dummy variables for low-dimensional factors
##################
factorCols <- colnames(ts1)[sapply(ts1, is.factor)]
highCardFacts <- colnames(ts1[,factorCols,with=FALSE])[sapply(ts1[,factorCols,with=FALSE], function(x) length(unique(x))>100)]

for(ii in highCardFacts) {
  print(ii)
  x <- data.frame(x1=ts1[, ii,with=FALSE])
  x[,ii] <- as.numeric(x[,ii])
  ts1[, paste(ii, "_num", sep="")] <- x
}


for(ii in highCardFacts) {
  print(ii)
  x <- data.frame(x1=ts1[, ii,with=FALSE])
  colnames(x) <- "x1"
  x$x1 <- as.numeric(x$x1)
  sum1 <- sqldf("select x1, sum(1) as cnt
                from x  group by 1 ")
  tmp <- sqldf("select cnt from x a left join sum1 b on a.x1=b.x1")
  ts1[, paste(ii, "_cnt", sep="")] <- tmp$cnt
}

ts1 <- ts1[,!colnames(ts1) %in% highCardFacts,with=FALSE]

dummy <- dummyVars( ~. -1, data = ts1[,1:ncol(ts1),with=FALSE])
ts1_dum <- data.frame(predict(dummy, ts1[,1:ncol(ts1),with=FALSE]))


###################
## Write CSV file
###################
ts1_dum <- ts1_dum[order(ts1_dum$filter, ts1_dum$ID),]
write_csv(ts1_dum, "./data_trans/ts1Trans_v1.csv")




