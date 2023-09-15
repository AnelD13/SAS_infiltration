# SAS_infiltration

## Summary of process
I had code developed in R for my MSc thesis, but a portion of it had to be converted to SAS.  
- Import xlsx file with data
- Use infiltration and time data recorded in the filed (infiltrationraw.xlsx) to calculate the slope (Sorptivity/2) and intercept (Kfs) values for each treatment*block combination
- Plot the curves for the raw data to check for outliers
- Combine Sorptivity and Kfs values along with Time, Infiltration and CI from an imported xlsx sheet (outliers removed) into a new table (InfilDF)
- Use InfilDF to run the non-linear Phillip's sorptivity model with predicted CI as output and combine into a new table
- Convert new table to long format to use it in a figure plotting infiltration against cumulative infiltration and predicted CI
- Option to restrict plotting to, for example, 2 hours (for consistency)
- 'infilsum.xlsx' will be used to model linear variables using glimmix - code wasn't necessary for this exercise
- 'infilsumraw.xlsx' was used to check for outliers - not used in this code
- Export tables to xlsx files

## Procedures used
- `PROC IMPORT` - for importing xlsx files
- `PROC SQL` - to set p a new data frame
- macros with `PROC REG` & loops - to calculate Sorptivity and Kfs values
- `PROC EXPORT` - for exporting xlsx files
- `PROC FORMAT` - for changing labels to be used in graphs
- `PROC SGPANEL` with ods graphics on/off - one pnale plot with `SERIES` and `SCATTER` input, the other with the `LOESS` statement
- `PROC CONTENTS` - to check variable types
- `PROC NLIN` - running non linear model
- `PROC SORT` and `PROC PRINT` for sorting and vieweing output
- `PROC TRANSPOSE` - to change data to long format
- `PROC FREQ` - to check unique levels of treatment

## SAS version details
![Sas version](https://github.com/AnelD13/SAS_infiltration/assets/126522316/7e6eae05-fcfd-4f39-bca7-df3f0b9b70b7)
