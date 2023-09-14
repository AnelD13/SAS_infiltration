/********************************
		Import dataset
*********************************/
/* set library / directory name - optional but will make sure that all inputs and outputs run
from and to this directory  */
libname InfiltrationFolder 'C:\Users\aneld\OneDrive\Documents\My SAS Files\Infiltration';

/* Use proc import instead of copying data set into SAS*/
title Infiltration Raw;
proc import out=infiltrationraw
	datafile='C:\Users\aneld\OneDrive\Documents\My SAS Files\Infiltration\InfiltrationRaw.xlsx'
	dbms=xlsx /*specify file type*/
	replace; /* replace file if it exists*/
	/*delimiter=','; /*optional specification*/
	range='Infiltrationraw$A1:J247'; /*first item is the sheetname, then the cell range */
run;
proc print data=infiltrationraw;
run;


/**********************************
CALCULATE SORPTIVITY AND Kfs VALUES
**********************************/
title Calculate slope and intercept values;
/* create empty data frame */
data InfilNewData;
  length Block $6 Treatment $ 15. Slope 4 Kfs 4; /* Define variable types and lengths */
  keep Block Treatment Slope Kfs;
  stop;
run;

proc sql;
  select distinct Treatment into :treatment_list separated by ' ' from infiltrationraw;
quit;

%macro S_K_regression(treatment, block, InfilNewData); /* Filter the data for the current treatment */
ods graphics off; /* disables the creation of function related plots as external jpg files */	
data treatment_data;
    set infiltrationraw;
    where Treatment = "&treatment" and Block = "&block";
  run;

  proc reg data=treatment_data outest=reg_out; /* Perform linear regression */
    model fp = thalf;
  run;

  data slope_intercept; /* Calculate the slope and intercept */
    set reg_out;
    Slope = thalf;
    Kfs = intercept;
    Block = "&block";
    Treatment = "&treatment";
	length Block $6 Treatment $ 15. Slope 4 Kfs 4;
  run;

  proc append base=InfilNewData data=slope_intercept force; /* Append the results to the main dataframe */
  run;

  proc datasets library=work nolist; /* Clear temporary datasets */
    delete treatment_data reg_out slope_intercept;
  run;
  quit;
%mend;

/* Loop through each block */
%macro calculate_S_K;
  %do treatment_index = 1 %to %sysfunc(countw(&treatment_list));
    %let treatment = %scan(&treatment_list, &treatment_index);
    /* Loop through each block for the current treatment */
    %do block_index = 1 %to &num_blocks; /* Assuming you have a macro variable num_blocks with the number of unique blocks */
      %let block = Block&block_index;
      /* Call the regression macro for the current treatment and block */
      %S_K_regression(&treatment, &block, InfilNewData);
    %end;
  %end;
%mend;
proc sql; /* Initialize the number of unique blocks */
  select count(distinct Block) into :num_blocks from infiltrationraw;
quit;
%calculate_S_K(treatment_list); /* Call the macro to process all treatment-block combinations */

proc print data=InfilNewData;
run;

/* Create column for sorptivity which is slope * 2 & rename intercept to K */
data InfilNewData;
  set InfilNewData;
  Sorptivity = Slope * 2;
run;

proc print data=InfilNewData;
run;

/* Export the results to an Excel xlsx file */
proc export data=InfilNewData
  outfile='Slope and Intercept.xlsx'
  dbms=xlsx replace;
  sheet='Sheet1';
run;



/********************************
  Check raw infiltration curves
*********************************/
/* Create a custom format for the 'Treatment' variable */
/***  ONLY USE THIS FOR GRAPHS
		ONLY RUN GRAPHS AFTER OTHER CODE IN A SPECIFIC SCTION ***/
proc format;
  value $ TreatmentFmt
    'Control1' = 'Control 1'
    'Control2' = 'Control 2'
    'Biochar25kgPha' = 'Biochar 25kgP/ha'
	'Biochar10thaTSP' = 'Biochar 10t/ha & TSP'
	'Biochar10tha' = 'Biochar 10t/ha'
    'Phosphorus' = 'TSP Fertilizer';
run;

/* change data set to take into account above label changes */
data infiltrationraw;
  set infiltrationraw;
  format Treatment $ TreatmentFmt.;
  run;

/* Save the plot as an image file */
ods graphics on / 
	width=20in /* play with sizes to change output*/
	height=16in
	outputfmt=png
	imagemap=on
	imagename = 'InfiltrationRaw';
  /* Create the plot sgpanel splits treatments into separate panels*/
  /* sgpanel does not seem to support error bands*/
proc sgpanel data=infiltrationraw;
	panelby Treatment / columns=3 uniscale=all;
	scatter x=TimeH y=CI / group=Block markerattrs=(size=8 symbol=circlefilled);
	series x=TimeH y=CI / group=Block markerattrs=(size=5) /*adds line*/
		linearrts=(pattern=1);
	styleattrs  datacontrastcolors=(red blue black yellow);
	colaxis label="Time (hours)"; /* for x axis */
	rowaxis label="Cumulative Infiltration (mm)"; /* for y axis */
run;
ods graphics off;



/********************************
  Infiltration outliers removed
*********************************/
/*** Used for merging datasets and calculating predicted values ***/
/* make sure data is in correct format, e.g. hours, cm, etc.)*/
/* load data */
title Infiltration;
proc import out=infiltration
	datafile='C:\Users\aneld\OneDrive\Documents\My SAS Files\Infiltration\Infiltration.xlsx'
	dbms=xlsx
	replace;
	range='Infiltration$A1:E238';
	options msglevel=i;
run;

proc print data=infiltration;
run;

/* Create new dataframe with only wanted variables from 'infiltration' and 'InfilNewData'*/
proc sql;
    create table InfilDF as
    select A.Block, A.Treatment, A.Time, A.CI, A.Infiltration, B.Sorptivity, B.Kfs
    from infiltration as A
    left join InfilNewData as B
    on A.Treatment = B.Treatment and A.Block = B.Block;
quit;

data InfilDF; /* optional step to convert variable units, skip if excel file contains correct units*/
	set InfilDF;
	Time = Time/3600; /* convert seconds to hours if not already done */
	format Time best4.2; /*display time with 4 characters of which 2 are decimal */
	CI = CI/10; /*convert mm to cm if not already done*/
	Infiltration = Infiltration/10;
run;
proc sort data=InfilDF;
by Treatment Block Time;
run;
proc print data=InfilDF;
run;
/* confirm variable types */
proc contents data=InfilDF varnum;
run;

/*************
Model the data
*************/
proc means data=InfilDF;
  by Treatment Block;
  var Sorptivity Kfs;
  output out=SummaryData(drop=_TYPE_ _FREQ_) mean(Sorptivity Kfs)=;
run;

/* Define a macro to run the non-linear model for each Treatment group */
options spool;
%macro run_model(treatment, block, time, ci, s, k);
data temp;/* Create local macro variables */
	merge infiltration  (where=(Treatment = "&treatment" and Block = "&block"))
		InfilNewData  (where=(Treatment = "&treatment" and Block = "&block"));
	by Treatment Block;
	Time = &time;
	CI = &ci;
	Sorptivity = &s;
	Kfs = &k;
run;
proc nlin data=temp;
	parms Sorptivity = &s Kfs = &k;
	model CI = Sorptivity * sqrt(Time) + Kfs;
	output out=PredictedCI_&treatment Block=Block Time=Time CI=CI Sorptivity=Sorptivity Kfs=Kfs predicted=PredictedCI;
run;
data PredictedCI_&treatment;/* Add a Treatment group identifier to the output */
	set PredictedCI_&treatment;
	Treatment = "&treatment";
	Block = "&block";
run;
%mend;

%macro run_all_models;
%local treatment_list block_list s_list k_list time_list ci_list;
/* Create macro variable lists within the macro */
proc sql noprint;
  select distinct Treatment into :treatment_list separated by ' ' from InfilDF;
  select distinct Block into :block_list separated by ' ' from InfilDF;
  select distinct Sorptivity into :s_list separated by ' ' from InfilNewData;
  select distinct Kfs into :k_list separated by ' ' from InfilNewData;
  select distinct Time into :time_list separated by ' ' from InfilDF;
  select distinct CI into :ci_list separated by ' ' from InfilDF;
quit;
/* Loop over the macro variables and run the models */
%do i = 1 %to %sysfunc(countw(&treatment_list));
	%let current_treatment = %scan(&treatment_list, &i);
	%let current_block = %scan(&block_list, &i);
	%let current_s = %scan(&s_list, &i);
	%let current_k = %scan(&k_list, &i);
	%let current_time = %scan(&time_list, &i);
	%let current_ci = %scan(&ci_list, &i);
	%run_model(&current_treatment, &current_block, &current_time, &current_ci, &current_s, &current_k);
	proc print data=PredictedCI_&current_treatment;
	run;
%end;
%mend;

%run_all_models;






/********************************
 	   Infiltration summary
*********************************/
/****   Used only for modelling differences between K, S, initial and final infiltration, 
		slope and moisture ***/

/* load data */
title Infiltration Summary;
proc import out=infilsum
	datafile='C:\Users\aneld\OneDrive\Documents\My SAS Files\Infiltration\InfilSum.xlsx'
	dbms=xlsx
	replace;
	getnames=yes;
proc print data=infilsum;
run;


/* Use the normal glmmix model to run the K, S, initial & final infiltration, slope and moisture values */
