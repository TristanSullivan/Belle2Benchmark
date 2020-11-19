#!/bin/bash

#set -x # enable debug printouts

#set -e # immediate exit on error

# Function doOne must be defined in each benchmark
# Input argument $1: process index (between 1 and $NCOPIES)
# Return value: please return 0 if this workload copy was successful, 1 otherwise
# The following variables are guaranteed to be defined and exported: NCOPIES, NTHREADS, NEVENTS_THREAD, BMKDIR, DEBUG
# The function is started in process-specific working directory <basewdir>/proc_$1:
# please store here the individual log files for each of the NCOPIES processes
function doOne(){
  if [ "$1" == "" ] || [ "$2" != "" ]; then echo "[doOne] ERROR! Invalid arguments '$@' to doOne"; return 1; fi
  echo "[doOne ($1)] $(date) starting in $(pwd)"
  echo "[doOne ($1)] do one! (process $1 of $NCOPIES)"

  # Configure WL copy
  curdir=`pwd`
  export BELLE2_CONDB_SERVERLIST=/cvmfs/belle.cern.ch/conditions/database.sqlite
  cat > SConscript <<EOT
Import('env')
# This file specifies the dependencies of your Analyis code to parts of the
# Belle 2 Software. It should be fine for most analysis but if you need to link
# against additional libraries pleas put them here.
env['LIBS'] = [
    'mdst_dataobjects',
    'analysis_dataobjects',
    'analysis',
    'framework',
    '\$ROOT_LIBS',
]
Return('env')
EOT
  
  echo release-05-01-05 > .analysis 
  source /cvmfs/belle.cern.ch/tools/b2setup release-05-01-05
  ln -s $BMKDIR/bmk.py bmk.py

  # Execute WL copy
  echo "Executing the following number of threads:"
  echo $NTHREADS

  # Ignore requests for multi-threading
  basf2 bmk.py -n $(( $NEVENTS_THREAD ))  > $curdir/output
  status=$?

  cd $curdir
  #echo "_________________________________________________OUTPUT START_________________________________________________"
  cat output
  #echo "_________________________________________________OUTPUT END_________________________________________________"

  echo "[doOne ($1)] $(date) completed (status=$status)"
  # Return 0 if this workload copy was successful, 1 otherwise
  return $status
}

# Optional function validateInputArguments may be defined in each benchmark
# If it exists, it is expected to set NCOPIES, NTHREADS, NEVENTS_THREAD
# (based on previous defaults and on user inputs USER_NCOPIES, USER_NTHREADS, USER_NEVENTS_THREADS)
# Input arguments: none
# Return value: please return 0 if input arguments are valid, 1 otherwise
# The following variables are guaranteed to be defined: NCOPIES, NTHREADS, NEVENTS_THREAD
# (benchmark defaults) and USER_NCOPIES, USER_NTHREADS, USER_NEVENTS_THREADS (user inputs)
function validateInputArguments(){
  if [ "$1" != "" ]; then echo "[validateInputArguments] ERROR! Invalid arguments '$@' to validateInputArguments"; return 1; fi
  echo "[validateInputArguments] validate input arguments"
  # Dummy version: accept user inputs as they are
  if [ "$USER_NCOPIES" != "" ]; then NCOPIES=$USER_NCOPIES; fi
  if [ "$USER_NTHREADS" != "" ]; then NTHREADS=$USER_NTHREADS; fi
  if [ "$USER_NEVENTS_THREAD" != "" ]; then NEVENTS_THREAD=$USER_NEVENTS_THREAD; fi
  # Return 0 if input arguments are valid, 1 otherwise
  return 0
}

# Optional function usage_detailed may be defined in each benchmark
# Input arguments: none
# Return value: none
function usage_detailed(){
  echo "NCOPIES*NTHREADS may be lower or greater than nproc=$(nproc)"
}

# Default values for NCOPIES, NTHREADS, NEVENTS_THREAD must be set in each benchmark
NTHREADS=1
NCOPIES=$(( `nproc` / $NTHREADS )) # (do not use NTHREADS=1, to allow tests that this can be changed)
NEVENTS_THREAD=50

# Source the common benchmark driver
if [ -f $(dirname $0)/bmk-driver.sh ]; then
  . $(dirname $0)/bmk-driver.sh
else
  . $(dirname $0)/../../../common/bmk-driver.sh
fi
