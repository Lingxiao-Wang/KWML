#################################################################################################
## ipsw.wt is a function calculating pseudo weights using IPSW methods                         ##
## INPUT:  psa_dat  - dataframe of the combined cohort and survey sample                       ##
##         wt       - name of the weight variable in psa_dat                                   ##
##                    (common weights of 1 for cohort, and sample weights for survey)          ##
##         rsp_name - name of the cohort membership indicator in psa_dat                       ##
##         formula  - formula of the regression model                                          ##
## OUTPUT: a vector of IPSW pseudo weights                                                     ##
#################################################################################################

ipsw.wt = function(psa_dat, wt, rsp_name, formula){
    ds = svydesign(ids=~1, weight = as.formula(paste("~", wt)), data = psa_dat)
    lgtreg = svyglm(as.formula(formula), family = binomial, design = ds)
    # Predict propensity scores
    p_score = lgtreg$fitted.values
    p_score.c = p_score[psa_dat[,rsp_name]==1]
	ipsw.wt = as.vector((1-p_score.c)/p_score.c)
	ipsw.wt
}

###################################################################################################
## kw.wt_out is a function calculating KW pseudo weights using logistic regression propensity    ##
##           model to predict propensity scores                                                  ##
## INPUT:  psa_dat  - dataframe of the combined cohort and survey sample                         ##
##         rsp_name - name of the cohort membership indicator in psa_dat                         ##
##                    (1 for cohort units, and 0 for survey units)                               ##
##         formula  - formula of the regression model                                            ##
##         svy.wt   - a vector of survey weights                                                 ##
##         h        - bandwidth parameter                                                        ##
##                    (default is NULL, and will be calculated corresponding to kernel function) ##
##         krnfun   - kernel function                                                            ##
##                    "triang": triangular density on (-3, 3)                                    ##
##                    "dnorm":  standard normal density                                          ##
##                    "dnorm_t":truncated standard normal densigy on (-3, 3)                     ##
##         Large    - if the cohort size is so large that the survey sample has to be divided    ##
##                    into pieces for calculation convenience. Default is FALSE                  ##
##         rm.s     - removing unmatched survey units or not. Default is FALSE                   ##
## OUTPUT: psd.wt     - KW pseudo weights                                                        ##
##         delt.svy.s - number of unmatched survey sample units                                  ##
##         h          - bandwidth                                                                ##
###################################################################################################

kw.wt_out = function(psa_dat, rsp_name, formula, svy.wt,
                     h=NULL, krn="triang", Large = F, rm.s = F){
	n = dim(psa_dat)[1]
    svyds = svydesign(ids =~1, weight = rep(1, n), data = psa_dat)
    lgtreg = svyglm(formula, family = binomial, design = svyds)
    p_score = lgtreg$fitted.values
    # Propensity scores for the cohort
    p_score.c = p_score[psa_dat[,rsp_name]==1]
    # Propensity scores for the survey sample
    p_score.s = p_score[psa_dat[,rsp_name]==0]
    out = kw.wt(p_score.c = p_score.c, p_score.s = p_score.s,
          svy.wt = svy.wt, h=h, krn= krn, Large = Large, rm.s = rm.s)
   return(list(pswt = out$pswt, delt.svy = out$delt.svy, h = out$h))
 }


###################################################################################################
## kw.wt is a function calculating KW pseudo weights given the propensity scores                 ##
## INPUT:  p_score.c - predicted propensity score for cohort                                     ##
##         p_score.s - predicted propensity score for survey                                     ##
##         svy.wt    - a vector of survey weights                                                ##
##         h         - bandwidth parameter                                                       ##
##                     (will be calculated corresponding to kernel function if not specified).   ##
##         krnfun    - kernel function                                                           ##
##                     "triang": triangular density on (-3, 3)                                   ##
##                     "dnorm":  standard normal density                                         ##
##                     "dnorm_t":truncated standard normal densigy on (-3, 3)                    ##
##         Large     - if the cohort size is so large that it has to be divided into pieces      ##
##         rm.s      - removing unmatched survey units or not. Default is FALSE                  ##
## OUTPUT: psd.wt    - KW pseudo weights                                                         ##
##         sum_0.s   - number of unmatched survey sample units                                   ##
## WARNINGS:                                                                                     ##
##         If there are unmatched survey sample units, the program gives                         ##
##         "The input bandwidth h is too small. Please choose a larger one!"                     ##
##           If rm.s=T, the program deletes unmatched survey sample units, and gives             ##
##           a warning "records in the prob sample were not used because of a small bandwidth"   ##
##           If rm.s=F, the program evenly distribute weights of unmatched survey sample units   ##
##           to all cohot units.                                                                 ##
###################################################################################################

kw.wt = function(p_score.c, p_score.s, svy.wt, h=NULL, mtch_v = NULL, krn="triang", Large = F, rm.s = F){
  # get the name of kernel function
  # calculate bandwidth according to the kernel function
  #triangular density
  if(krn=="triang")h = bw.nrd0(p_score.c)/0.9*0.8586768
  if(krn=="dnorm"|krn=="dnorm_t")h = bw.nrd0(p_score.c)
  krnfun = get(krn)
  # create signed distance matrix
  m = length(p_score.c)
  n = length(p_score.s)
    if (Large == F){
    sgn_dist_mtx = outer(p_score.s, p_score.c, FUN = "-")
    krn_num = krnfun(sgn_dist_mtx/h)
    if(is.null(mtch_v)){
      adj_m = 1
    }else{adj_m=outer(mtch_v[1:n], mtch_v[(n+1):(n+m)], FUN='==')}
    krn_num = krn_num*adj_m
    row.krn = rowSums(krn_num)
    sum_0.s = (row.krn==0)
    delt.svy = sum(sum_0.s)
    if(delt.svy>0){
      warning('The input bandwidth h is too small. Please choose a larger one!')
      if(rm.s == T){
        warning(paste(sum(sum_0.s), "records in the prob sample were not used because of a small bandwidth"))
        row.krn[sum_0.s]=1
      }else{
        krn_num[sum_0.s,]= 1
        row.krn[sum_0.s] = m
      }
    }
    row.krn = rowSums(krn_num)
    krn = krn_num/row.krn
    # QC: column sums should be 1 if rm.s=F; otherwise, some column sums could be 0
    #round(sum(rowSums(krn)),0) == round(dim(sgn_dist_mtx)[1],0) # TRUE
    #sum(rowSums(krn))== (dim(sgn_dist_mtx)[1]-sum(sum_0.s)) # TRUE
    # Final pseudo weights
    pswt_mtx = krn*svy.wt
    # QC: row sums should be weights for the survey sample
    # If rm.s = T, some of the survey sample units are not used.
    #svy.wt.u = svy.wt
    #svy.wt.u[sum_0.s]=0
    #sum(round(rowSums(pswt_mtx), 10) == round(svy.wt.u, 10))== dim(sgn_dist_mtx)[1]   #True
    psd.wt = colSums(pswt_mtx)
    # QC: sum of pseudo weights is equal to sum of survey sample weights
    #sum(psd.wt) == sum(svy.wt.u)       #True
  }else{
    psd.wt = rep(0, m)
    grp_size =  floor(n/50)
    up = c(seq(0, n, grp_size)[2:50], n)
    lw = seq(1, n, grp_size)[-51]
    delt.svy = 0
    for(g in 1:50){
      sgn_dist_mtx = outer(p_score.s[lw[g]:up[g]], p_score.c, FUN = "-")
      krn_num = krnfun(sgn_dist_mtx/h)
      if(is.null(mtch_v)){
        adj_m = 1
      }else{adj_m=outer(mtch_v[lw[g]:up[g]], mtch_v[(n+1):(n+m)], FUN='==')}
      krn_num = krn_num*adj_m
      row.krn = rowSums(krn_num)
      sum_0.s = (row.krn==0)
      delt.svy = delt.svy + (sum(sum_0.s)>0)
      if((sum(sum_0.s)>0)){
        warning('The input bandwidth h is too small. Please choose a larger one!')
        if(rm.s == T){
          warning(paste(sum(sum_0.s), "records in the prob sample were not used because of a small bandwidth"))
          row.krn[sum_0.s]=1
        }else{
          krn_num[sum_0.s,]= 1
          row.krn[sum_0.s] = m
        }
      }
      row.krn = rowSums(krn_num)
      krn = krn_num/row.krn
      # QC: column sums should be 1 if rm.s=F; otherwise, some column sums could be 0
      #round(sum(rowSums(krn)),0) == round(dim(sgn_dist_mtx)[1],0) # TRUE
      #sum(rowSums(krn))== (dim(sgn_dist_mtx)[1]-sum(sum_0.s)) # TRUE
      # Final psuedo weights
      pswt_mtx = krn*svy.wt[lw[g]:up[g]]
      # QC: row sums should be weights for the survey sample
      # If rm.s = T, some of the survey sample units are not used.
      #svy.wt.u = svy.wt
      #svy.wt.u[sum_0.s]=0
      #sum(round(rowSums(pswt_mtx), 10) == round(svy.wt.u, 10))== dim(sgn_dist_mtx)[1]   #True
      psd.wt = colSums(pswt_mtx) + psd.wt
    }
  }

  return(list(pswt = psd.wt, delt.svy = delt.svy, h = h))
} # end of kw.wt


######################################################################################################
## kw.mob is a function calculating KW pseudo weights using MOB method to predict propensity scores ##
## INPUT:  psa_dat  - dataframe of the combined cohort and survey sample                            ##
##         tune_maxdepth - tunning parameter(s)                                                     ##
##         wt       - name of the weight variable in psa_dat                                        ##
##                    (common weights of 1 for cohort, and sample weights for survey)               ##
##         formula  - formula of the propensity model                                               ##
##         rsp_name - name of the cohort membership indicator in psa_dat                            ##
##                    (1 for cohort units, and 0 for survey units)                                  ##
##         svy.wt   - a vector of survey weights                                                    ##
##         covars   - a vector of covariate names for SMD calculation                               ##
##         h        - bandwidth parameter                                                           ##
##                    (default is NULL, and will be calculated corresponding to kernel function)    ##
##         krnfun   - kernel function                                                               ##
##                    "triang": triangular density on (-3, 3)                                       ##
##                    "dnorm":  standard normal density                                             ##
##                    "dnorm_t":truncated standard normal densigy on (-3, 3)                        ##
##         Large    - if the cohort size is so large that the survey sample has to be divided       ##
##                    into pieces for calculation convenience. Default is FALSE                     ##
##         rm.s     - removing unmatched survey units or not. Default is FALSE                      ##
## OUTPUT: iter     - number of iteration for reaching convergence in SMD                           ##
##         kw.mob   - a dataframe including kw weights for each tunning parameter                   ##
##         smds     - a vector of SMD for cohort with each set of kw weight                         ##
######################################################################################################

kw.mob = function(psa_dat, wt, tune_maxdepth, formula, svy.wt, rsp_name, covars,
                     h=NULL, krn="triang", Large = F, rm.s = F){
  psa_dat$wt_kw.tmp <- psa_dat[, wt]
  n_c = sum(psa_dat[, rsp_name]==1)
  n_s = sum(psa_dat[, rsp_name]==0)
  p_score       <- data.frame(matrix(ncol = length(tune_maxdepth), nrow = nrow(psa_dat)))
  p_score_c.tmp <- data.frame(matrix(ncol = length(tune_maxdepth), nrow = n_c))
  p_score_s.tmp <- data.frame(matrix(ncol = length(tune_maxdepth), nrow = n_s))
  smds <- rep(NA, length(tune_maxdepth)+1)
  smds[1] <- mean(abs(bal.tab(psa_dat[, covars], treat = psa_dat[, rsp_name], weights = psa_dat[, wt],
                     s.d.denom = "pooled", binary = "std", method="weighting")$Balance[, "Diff.Adj"]))
  i <- 0
  kw_tmp = as.data.frame(matrix(0, n_c, length(tune_maxdepth)))
  # Loop over try-out values
  repeat {
    i <- i+1
    # Run model
    maxdepth <- tune_maxdepth[i]
    mob <- glmtree(formula,
                   data = psa_dat,
                   family = binomial,
                   alpha = 0.05,
                   minsplit = NULL,
                   maxdepth = maxdepth)
    p_score[, i]       <- predict(mob, psa_dat, type = "response")
    p_score_c.tmp[, i] <- p_score[psa_dat$trt == 1, i]
    p_score_s.tmp[, i] <- p_score[psa_dat$trt == 0, i]
    # Calculate KW weights
    kw_tmp[,i] <- kw.wt(p_score.c = p_score_c.tmp[,i], p_score.s = p_score_s.tmp[,i],
                       svy.wt = svy.wt, Large=F)$pswt
    # Calculate covariate balance
    psa_dat$wt_kw[psa_dat$trt == 1] <- kw_tmp[,i]
    smds[i+1] <- mean(abs(bal.tab(psa_dat[, covars], treat = psa_dat[, rsp_name], weights = psa_dat$wt_kw,
                                  s.d.denom = "pooled", binary = "std", method = "weighting")$Balance[, "Diff.Adj"]))
    # Check improvement in covariate balance
    if (abs(smds[i] - smds[i+1]) < 0.001 | length(tune_maxdepth) == i) break
  }
  return(list(iter = i, kw_tmp = kw_tmp, smds = smds, p_score_c.tmp = p_score_c.tmp, p_score_s.tmp = p_score_s.tmp))
}


######################################################################################################
## kw.crf is a function calculating KW pseudo weights using conditional random forest
##        method to predict propensity scores ##
## INPUT:  psa_dat  - dataframe of the combined cohort and survey sample                            ##
##         tune_mincriterion - tunning parameter(s)                                                     ##
##         wt       - name of the weight variable in psa_dat                                        ##
##                    (common weights of 1 for cohort, and sample weights for survey)               ##
##         formula  - formula of the propensity model                                               ##
##         rsp_name - name of the cohort membership indicator in psa_dat                            ##
##                    (1 for cohort units, and 0 for survey units)                                  ##
##         svy.wt   - a vector of survey weights                                                    ##
##         covars   - a vector of covariate names for SMD calculation                               ##
##         h        - bandwidth parameter                                                           ##
##                    (default is NULL, and will be calculated corresponding to kernel function)    ##
##         krnfun   - kernel function                                                               ##
##                    "triang": triangular density on (-3, 3)                                       ##
##                    "dnorm":  standard normal density                                             ##
##                    "dnorm_t":truncated standard normal densigy on (-3, 3)                        ##
##         Large    - if the cohort size is so large that the survey sample has to be divided       ##
##                    into pieces for calculation convenience. Default is FALSE                     ##
##         rm.s     - removing unmatched survey units or not. Default is FALSE                      ##
## OUTPUT: iter     - number of iteration for reaching convergence in SMD                           ##
##         kw.rf    - a dataframe including kw weights for each tunning parameter                   ##
##         smds     - a vector of SMD for cohort with each set of kw weight                         ##
######################################################################################################

kw.crf = function(psa_dat, wt, tune_mincriterion, formula, svy.wt, rsp_name, covars,
                  h=NULL, krn="triang", Large = F, rm.s = F){
  psa_dat$wt_kw.tmp <- psa_dat[, wt]
  n_c = sum(psa_dat[, rsp_name]==1)
  n_s = sum(psa_dat[, rsp_name]==0)
  p_score       <- data.frame(matrix(ncol = length(tune_maxdepth), nrow = nrow(psa_dat)))
  p_score_c.tmp <- data.frame(matrix(ncol = length(tune_maxdepth), nrow = n_c))
  p_score_s.tmp <- data.frame(matrix(ncol = length(tune_maxdepth), nrow = n_s))
  smds <- rep(NA, length(tune_mincriterion))
  smds[1] <- mean(abs(bal.tab(psa_dat[, covars], treat = psa_dat[, rsp_name], weights = psa_dat[, wt],
                              s.d.denom = "pooled", binary = "std", method="weighting")$Balance[, "Diff.Adj"]))
  kw_tmp = as.data.frame(matrix(0, n_c, length(tune_mincriterion)))
  # Loop over try-out values
  for (i in seq_along(tune_mincriterion)){
    minc <- tune_mincriterion[i]
    crf <- cforest(formula,
                   data = psa_dat,
                   control = ctree_control(mincriterion = minc),
                   ntree = 100)
    p_score[, i]       <- predict(crf, newdata = psa_dat, type = "prob")[, 2]
    p_score_c.tmp[, i] <- p_score[psa_dat$trt == 1, i]
    p_score_s.tmp[, i] <- p_score[psa_dat$trt == 0, i]
    # Calculate KW weights
    kw_tmp[,i] <- kw.wt(p_score.c = p_score_c.tmp[,i], p_score.s = p_score_s.tmp[,i],
                        svy.wt = svy.wt, Large=F)$pswt
    # Calculate covariate balance
    psa_dat$wt_kw[psa_dat$trt == 1] <- kw_tmp[,i]
    smds[i+1] <- mean(abs(bal.tab(psa_dat[, covars], treat = psa_dat$trt, weights = psa_dat$wt_kw,
                                  s.d.denom = "pooled", binary = "std", method = "weighting")$Balance[, "Diff.Adj"]))
    }

  return(list(kw_tmp = kw_tmp, smds = smds, p_score_c.tmp = p_score_c.tmp, p_score_s.tmp = p_score_s.tmp))
}


######################################################################################################
## kw.gbm is a function calculating KW pseudo weights using Gradient Tree Boosting
##        method to predict propensity scores ##
## INPUT:  psa_dat  - dataframe of the combined cohort and survey sample                            ##
##         tune_idepth - tuning parameter(s)
##         tune_ntree - tuning parameter(s)
##         wt       - name of the weight variable in psa_dat                                        ##
##                    (common weights of 1 for cohort, and sample weights for survey)               ##
##         formula  - formula of the propensity model                                               ##
##         rsp_name - name of the cohort membership indicator in psa_dat                            ##
##                    (1 for cohort units, and 0 for survey units)                                  ##
##         svy.wt   - a vector of survey weights                                                    ##
##         covars   - a vector of covariate names for SMD calculation                               ##
##         h        - bandwidth parameter                                                           ##
##                    (default is NULL, and will be calculated corresponding to kernel function)    ##
##         krnfun   - kernel function                                                               ##
##                    "triang": triangular density on (-3, 3)                                       ##
##                    "dnorm":  standard normal density                                             ##
##                    "dnorm_t":truncated standard normal densigy on (-3, 3)                        ##
##         Large    - if the cohort size is so large that the survey sample has to be divided       ##
##                    into pieces for calculation convenience. Default is FALSE                     ##
##         rm.s     - removing unmatched survey units or not. Default is FALSE                      ##
## OUTPUT: iter     - number of iteration for reaching convergence in SMD                           ##
##         kw.rf    - a dataframe including kw weights for each tunning parameter                   ##
##         smds     - a vector of SMD for cohort with each set of kw weight                         ##
######################################################################################################

kw.gbm = function(psa_dat, wt, tune_idepth, tune_ntree, formula, svy.wt, rsp_name, covars,
                  h=NULL, krn="triang", Large = F, rm.s = F){
  psa_dat$wt_kw.tmp <- psa_dat[, wt]
  n_c = sum(psa_dat[, rsp_name]==1)
  n_s = sum(psa_dat[, rsp_name]==0)
  p_score_c.tmp <- data.frame(matrix(ncol = length(tune_idepth), nrow = n_c))
  p_score_s.tmp <- data.frame(matrix(ncol = length(tune_idepth), nrow = n_s))
  p_scores_i  <- data.frame(matrix(ncol = length(tune_ntree),  nrow = nrow(psa_dat)))
  p_score_i_s <- data.frame(matrix(ncol = length(tune_ntree),  nrow = n_c))
  p_score_i_c <- data.frame(matrix(ncol = length(tune_ntree),  nrow = n_s))
  smds_o <- rep(NA, length(tune_idepth))
  smds_i <- rep(NA, length(tune_ntree)+1)
  smds_i[1] <- mean(abs(bal.tab(psa_dat[, covars], treat = psa_dat[, rsp_name], weights = psa_dat[, wt],
                                s.d.denom = "pooled", binary = "std", method="weighting")$Balance[, "Diff.Adj"]))
  kw_tmp_o = as.data.frame(matrix(0, n_c, length(tune_idepth)))
  kw_tmp_i = as.data.frame(matrix(0, n_c, length(tune_ntree)))
  # Outer loop over try-out values
  for (i in seq_along(tune_idepth)){
    #print(i)
    idepth <- tune_idepth[i]
    j <- 0
    # Inner loop over try-out values
    repeat {
      j <- j+1
      # Run model
      ntree <- tune_ntree[j]
      boost <- gbm(formula, data = psa_dat,
                   distribution = "bernoulli",
                   n.trees = ntree,
                   interaction.depth = idepth,
                   shrinkage = 0.05,
                   bag.fraction = 1)
      p_scores_i[, j] <- predict(boost, psa_dat, n.trees = ntree, type = "response")
      p_score_i_c[, j] <- p_scores_i[psa_dat$trt == 1, j]
      p_score_i_s[, j] <- p_scores_i[psa_dat$trt == 0, j]
      # Calculate KW weights
      kw_tmp_i[, j] <- kw.wt(p_score.c = p_score_i_c[, j], p_score.s = p_score_i_s[,j],
                         svy.wt = samp.s$wt, Large=F)$pswt
      # Calculate covariate balance
      psa_dat$wt_kw[psa_dat$trt == 1] <- samp.c$kw
      smds_i[j+1] <- mean(abs(bal.tab(psa_dat[, covars], treat = psa_dat$trt, weights = psa_dat$wt_kw, s.d.denom = "pooled",
                                      binary = "std", method = "weighting")$Balance[, "Diff.Adj"]))
      # Check improvement in covariate balance
      if (abs(smds_i[j] - smds_i[j+1]) < 0.001 | length(tune_ntree) == j){
        print(paste0("gbm", j))
        break
      }
    }
    # Select best KW weights of current iteration
    best <- which.min(smds_i[2:(length(tune_ntree)+1)])
    p_score_c.tmp[,i] <- p_score_i_c[, best]
    p_score_s.tmp[,i] <- p_score_i_s[, best]
    kw_tmp_o[,i] = kw_tmp_i[, best]
    smds_o[i] <- min(smds_i[2:(length(tune_ntree)+1)], na.rm = T)
  }

  return(list(kw_tmp = kw_tmp_o, smds = smds_o, p_score_c.tmp = p_score_c.tmp, p_score_s.tmp = p_score_s.tmp))
}


#####################################################################################################################
## cmb_dat is a function for data preparation including removing missing values in cohort and survey sample,       ##
## combining the two samples                                                                                       ##
## INPUT:  chtsamp - cohort (a data frame including covariates of the propensity score model)                      ##
##         svysamp - survey sample (a data frame including weight variable and                                     ##
##                                  covariates of the propensity score model)                                      ##
##         svy_wt  - variable name of the survey weight (should be included in svysamp)                            ##
##         Formula - propensity score model, with the format of trt~covariate1+covariate2+...                      ##
## OUTPUT: cmb_dat - combined sample of non-missing cohort and survey sample units including varibles              ##
##                   covariates in propensity score model                                                          ##
##                   "trt" indicator of data source (1 for cohort units, 0 for survey sample units)                ##
##                   "wt" weight varaible (1 for cohort units, survey sample weights)                              ##
##         chtsamp - complete  sample (in terms of covariates)                                                     ##
##         svysamp - complete survey sample (in terms of covariates)                                               ##
## WARNINGS:                                                                                                       ##
##         1, missing values in covariates are not allowed. Records with missing values in the cohort are removed. ##
##         2, missing values in covariates are not allowed. Records with missing values in the survey sample       ##
##         are removed. The complete cases are reweighted. Missing completely at random is assumed.                ##
#####################################################################################################################

cmb_dat = function(chtsamp,svysamp,svy_wt, Formula){
  # Get names of the response variable and predictors for the propensity score estimation model
  Fml_names = all.vars(Formula)
  # Name of the response variable
  rsp_name = Fml_names[1]
  # Name of the predictors
  mtch_var = Fml_names[-1]

  # Remove incomplete records in the cohort, if there are any.
  chtsamp_sub = as.data.frame(chtsamp[, mtch_var])
  if(sum(is.na(chtsamp_sub))>0){
    cmplt.indx = complete.cases(chtsamp_sub)
    chtsamp_sub = chtsamp_sub[cmplt.indx, ]
    chtsamp = chtsamp[cmplt.indx,]
    warning("Missing values in covariates are not allowed. Records with missing values in the cohort are removed.")
  }
  # Remove incomplete survey sample, if there are any.
  svysamp_sub = as.data.frame(svysamp[, mtch_var])
  svy_wt.vec = c(svysamp[, svy_wt])
  if(sum(is.na(svysamp_sub))>0){
    cmplt.indx = complete.cases(svysamp_sub)
    svysamp_sub = svysamp_sub[cmplt.indx, ]
    svy_wt.vec = sum(svysamp[, svy_wt])/sum(svy_wt.vec[cmplt.indx])*svy_wt.vec[cmplt.indx]
    warning("Missing values in covariates are not allowed. Records with missing values in the survey sample are removed.
            The complete cases are reweighted. Missing completely at random is assumed.")
  }# end removing incomplete records
  # size of cohort (complete)
  m = dim(chtsamp_sub)[1]
  # size of survey sample (complete)
  n = dim(svysamp_sub)[1]
  # Combine the two complete samples
  # Set outcome variable for propensity score model
  chtsamp_sub[,rsp_name] = 1                 # z=1 for cohort sample
  svysamp_sub[,rsp_name] = 0                 # z=0 for survey sample
  names(chtsamp_sub) = c(mtch_var, rsp_name) # unify the variable names in cohort and survey sample
  names(svysamp_sub) = c(mtch_var, rsp_name)
  cmb_dat = rbind(chtsamp_sub, svysamp_sub)  # combine the two samples
  cmb_dat$wt = c(rep(1, m), svysamp[, svy_wt])
  return(list(cmb_dat = cmb_dat,
              chtsamp = chtsamp,
              svysamp = svysamp
              )
         )
}

#####################################################################################################################
## cmb_dat1 is a function combining the cohort and survey sample                                                   ##
## INPUT:  chtsamp - cohort (a data frame including covariates of the propensity score model)                      ##
##         svysamp - survey sample (a data frame including weight variable and                                     ##
##                                  covariates of the propensity score model)                                      ##
##         svy_wt  - variable name of the survey weight (should be included in svysamp)                            ##
##         Formula - propensity score model, with the format of trt~covariate1+covariate2+...                      ##
## OUTPUT: cmb_dat - combined sample of non-missing cohort and survey sample units including varibles              ##
##                   covariates in propensity score model                                                          ##
##                   "trt" indicator of data source (1 for cohort units, 0 for survey sample units)                ##
##                   "wt" weight varaible (1 for cohort units, survey sample weights)                              ##
#####################################################################################################################

cmb_dat1 = function(chtsamp,svysamp,svy_wt, Formula){
  # Get names of the response variable and predictors for the propensity score estimation model
  Fml_names = all.vars(Formula)
  # Name of the response variable
  rsp_name = Fml_names[1]
  # Name of the predictors
  mtch_var = Fml_names[-1]

  chtsamp_sub = as.data.frame(chtsamp[, mtch_var])
  svysamp_sub = as.data.frame(svysamp[, mtch_var])
  svy_wt.vec = c(svysamp[, svy_wt])
  m = dim(chtsamp_sub)[1]
  # size of survey sample (complete)
  n = dim(svysamp_sub)[1]
  # Combine the two complete samples
  # Set outcome variable for propensity score model
  chtsamp_sub[,rsp_name] = 1                 # z=1 for cohort sample
  svysamp_sub[,rsp_name] = 0                 # z=0 for survey sample
  names(chtsamp_sub) = c(mtch_var, rsp_name) # unify the variable names in cohort and survey sample
  names(svysamp_sub) = c(mtch_var, rsp_name)
  cmb_dat = rbind(chtsamp_sub, svysamp_sub)  # combine the two samples
  cmb_dat$wt = c(rep(1, m), svy_wt.vec)
  cmb_dat
}

### Kernels ##
# triangular density on (-3, 3)
triang = function(x){
  x[abs(x)>3]=3
  1/3-abs(x)/3^2
}
# triangular densigh on (-2.5, 2.5)
triang_2 = function(x){
  x[abs(x)>2.5]=2.5
  1/2.5-abs(x)/2.5^2
}
# normal density (0, sigma=3)
dnorm_3 = function(x) dnorm(x, sd=3)
# truncated normal on (-3, 3)
dnorm_t = function(x){
  c = integrate(dnorm, -3, 3)$value
  y=dnorm(x)/c
  y[y<=dnorm(3)/c]=0
  y
}
