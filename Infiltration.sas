/********************************
		Import dataset
*********************************/
/* set library / directory name - optional but will make sure that all inputs and outputs run
from and to this directory  */
libname libref 'C:\Users\aneld\OneDrive\Documents\My SAS Files\Infiltration';

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
  length Block $6 Treatment $ 25. Slope 4 Kfs 4; /* Define variable types and lengths */
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

data infiltration;
	length Block $ 6 Treatment $ 25; */make sure it's longer than needed in case of later renaming*/
	set infiltration; /*set data table only after the legth has been specified */
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

proc nlin data=InfilDF;
	parms Sorptivity=0.01 Kfs=0.01;
	model CI = Sorptivity * sqrt(Time) + Kfs;
	by Treatment Block;
	output out=PredictedResults predicted=PredictedCI;
run;
data InfilPredicted;
	retain Block Treatment Time CI Infiltration Sorptivity Kfs; /* I had to do this as my Time 
				variable showed up empty*/
	merge InfilDF PredictedResults;
    by Treatment Block;
run;
proc sort data=InfilPredicted;
by Treatment Block Time;
run;
proc print data=InfilPredicted;
run;
proc export data=InfilPredicted
  outfile='Infiltration_PredictedCI.xlsx'
  dbms=xlsx replace;
  sheet='Sheet1';
run;


/**************************
Plot the infiltration curve
**************************/
/* transpose data so all values are within one column */
proc transpose data=InfilPredicted out=Infil_long;
  by Treatment Block Time;
  var Infiltration CI PredictedCI;
run;
/* rename Treatment labels */
proc format; /* no need to repeat this, I just did it for ease of reference */
  value $ TreatmentFmt max.
    "Control1" = "Control_1"
    "Control2" = "Control_2"
    "Biochar25kgPha" = "Biochar_25kg_P/ha"
	"Biochar10tha" = "Biochar_10t/ha"
    "Biochar10thaTSP" = "Biochar_10t/ha_&_TSP" /*issue with recognising this and B10t/ha
				as diffeernt strings so _ is used*/
	"Phosphorus" = "TSP_Fertilizer";
run;
/* set new labels in long format table */
data Infil_long;
	set Infil_long;
	format Treatment $TreatmentFmt.;
run;
proc print data=Infil_long;
run;
proc freq data=Infil_long; /* Check unique levels of treatment */
  tables Treatment / out=TreatmentLevels(keep=Treatment);
run;

/* Save the plot as an image file */
ods graphics on / 
	width=20in /* play with sizes to change output*/
	height=16in
	outputfmt=png
	imagemap=on
	imagename = 'InfiltrationCurves';
proc sgpanel data=Infil_long;
  panelby Treatment / columns=3 uniscale=all novarname ; /*novarname removes the 'treatment' label */
  loess x=Time y=COL1 / group=_NAME_ smooth=0.5 lineattrs=(pattern=1) nomarkers; 
		/*higher number for 'smooth' will increase the look of the line (very staggered with lower numbers) */
	styleattrs datacontrastcolors= (red green black);
	colaxis label="Time (hours)";
  rowaxis label="Infiltration (cm)";
  keylegend / title="Legend";
run;
ods graphics off;


/*********************************
  Predicted CI to specific time
**********************************/
/* to cut off the predicted values at for example 2 hours, use the following */
data Infil_long_filtered;
  set Infil_long;
  where Time <= 2;
run;
proc print data=Infil_long_filtered;
run;
proc sgpanel data=Infil_long_filtered;
  panelby Treatment / columns=3 uniscale=all novarname ; /*novarname removes the 'treatment' label */
  loess x=Time y=COL1 / group=_NAME_ smooth=0.5 lineattrs=(pattern=1) nomarkers; 
		/*higher number for 'smooth' will increase the look of the line (very staggered with lower numbers) */
	styleattrs datacontrastcolors= (red green black);
	colaxis label="Time (hours)";
  rowaxis label="Infiltration (cm)";
  keylegend / title="Legend";
run;


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
