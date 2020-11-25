# ASRC Atmospheric Chemistry Data Processing Package

[![Build Status](https://travis-ci.org/ASRCsoft/atmoschem.datasets.svg?branch=master)](https://travis-ci.org/ASRCsoft/atmoschem.datasets) [![R build status](https://github.com/ASRCsoft/atmoschem.process/workflows/R-CMD-check/badge.svg)](https://github.com/ASRCsoft/atmoschem.process/actions) [![Codecov test coverage](https://codecov.io/gh/ASRCsoft/atmoschem.process/branch/master/graph/badge.svg)](https://codecov.io/gh/ASRCsoft/atmoschem.process?branch=master)

The ASRC Atmospheric Chemistry Data Processing Package processes atmospheric chemistry data from ASRC sites in New York State. It provides tools to generate reports and processed datasets from the ASRC's atmospheric chemistry data, and tools to visualize the data.

## Reproducing the routine chemistry dataset

### Requirements

- Linux
- R and R package dependencies
- PostgreSQL, and a user with permission to create and delete databases

The processing is currently very computationally intensive and requires about 8GB of RAM and 30GB of disk space.

To install the R package dependencies, run (from within R)

```R
install.packages('remotes')
remotes::install_deps('path/to/atmoschem.process')
```

replacing the path with the path on your computer. You may be need to install additional Linux packages required by the R packages.

### Creating the dataset

The dataset package can be generated by running (from a terminal)

```sh
cd path/to/atmoschem.process
make routine_dataset
```

You will be asked for the atmoschem server's data password (twice), which can be obtained from [the atmoschem website](http://atmoschem.asrc.cestm.albany.edu/).

## Viewing the data

The R package comes with a Shiny app for viewing the processing steps. After data has been processed, it can be opened from within R:

```R
library(atmoschem.process)
# Create a postgres database connection and atmoschem.process dataset object
dbcon = src_postgres(dbname = 'nysatmoschemdb', user = 'user')
nysac = etl('atmoschem.process', db = dbcon, dir = 'data')
# Open the Shiny app
view_processing(nysac)
```

## License

`atmoschem.process` is released under the open source MIT license.
